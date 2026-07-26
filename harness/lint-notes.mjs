#!/usr/bin/env node
// Personal OS note linter — the harness "verify" step.
//
// Zero dependencies by design. The OpenAI harness-engineering post favors small,
// fully-inspectable helpers over opaque packages ("rather than pulling in a
// generic p-limit-style package, we implemented our own map-with-concurrency
// helper"). So we hand-roll a tiny frontmatter parser instead of depending on a
// YAML library — the whole verifier stays legible to the next agent.
//
// Usage:
//   node harness/lint-notes.mjs            validate the vault (exit 1 on ERRORs)
//   node harness/lint-notes.mjs --garden   also surface freshness/gardening hints
//
// Philosophy (adapted from the harness-engineering post): guard the invariants
// centrally and leave local choices free, and keep blocking gates minimal — a
// fix-later nit shouldn't stall work. So only schema breakage is an ERROR (blocks
// commits); everything
// else is a WARN (reported, never blocks). Every message injects a remediation
// hint so the next agent can self-correct without a human.

import { readdirSync, readFileSync, lstatSync, existsSync } from "node:fs";
import { join, relative, basename } from "node:path";
import { homedir } from "node:os";

const ROOT = process.cwd();
const GARDEN = process.argv.includes("--garden");

// --- configuration ---------------------------------------------------------
// Code and agent config are not knowledge notes — `tools/` ships scripts with their
// own READMEs, `.claude/` holds agent skills/hooks. Walking them would demand vault
// frontmatter of ordinary documentation.
const IGNORE_DIRS = new Set([".git", ".claude", ".obsidian", "node_modules", ".trash", "tools"]);
const TYPES = ["project", "incident", "decision", "reference", "area", "dashboard"];
const STATUSES = ["idea", "active", "blocked", "done", "archived"];
const REQUIRED = ["title", "type", "status", "created", "updated"];
const AGENTS_MAX_LINES = 120; // AGENTS.md is a short index, not an encyclopedia
const NOTE_SOFT_LINES = 400;  // taste invariant: oversized notes should be split
const STALE_DAYS = 180;       // garden: notes untouched this long get a freshness hint

// Meta / harness docs are exempt from the *content-note* frontmatter schema.
// They are scaffolding, not knowledge notes. They still get lighter checks.
const EXEMPT = [
  /(^|\/)AGENTS\.md$/, /(^|\/)CLAUDE\.md$/, /^ARCHITECTURE\.md$/, /^README\.md$/,
  /^SETUP\.md$/, /^CONTRIBUTING\.md$/,
  /^docs\//, /^harness\//, /^templates\//, /^dashboards\//,
  /(^|\/)index\.md$/,
];
// Templates carry {{placeholders}} and example links — never scan them as live notes.
const WIKILINK_SKIP = [/^templates\//];

const isExempt = (rel) => EXEMPT.some((re) => re.test(rel));
const skipWikilinks = (rel) => WIKILINK_SKIP.some((re) => re.test(rel));

// --- tiny frontmatter parser (scalars + inline arrays; enough for the schema) -
function parseFrontmatter(text) {
  if (!text.startsWith("---")) return null;
  const end = text.indexOf("\n---", 3);
  if (end === -1) return null;
  const block = text.slice(text.indexOf("\n") + 1, end);
  const out = {};
  for (const raw of block.split("\n")) {
    const line = raw.replace(/\s+$/, "");
    if (!line.trim() || line.trimStart().startsWith("#")) continue;
    const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) continue;
    let [, key, val] = m;
    if (val.startsWith("[") && val.endsWith("]")) {
      out[key] = val
        .slice(1, -1)
        .split(",")
        .map((s) => s.trim().replace(/^["']|["']$/g, ""))
        .filter(Boolean);
    } else {
      out[key] = val.replace(/^["']|["']$/g, "");
    }
  }
  return out;
}

// strip fenced + inline code so example links in prose (in backticks) don't trip the scanner
function stripCode(text) {
  return text.replace(/```[\s\S]*?```/g, "").replace(/`[^`]*`/g, "");
}

function findWikilinks(text) {
  const links = [];
  const re = /\[\[([^\]]+)\]\]/g;
  let m;
  while ((m = re.exec(stripCode(text))) !== null) {
    const target = m[1].split("|")[0].split("#")[0].trim();
    if (target) links.push(target);
  }
  return links;
}

const isoDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s || "");
const isKebab = (s) => /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(s);

// --- walk the vault --------------------------------------------------------
function walk(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const st = lstatSync(full);
    if (st.isSymbolicLink()) continue; // e.g. nix build `result` -> /nix/store/...
    if (st.isDirectory()) {
      if (!IGNORE_DIRS.has(name)) walk(full, acc);
    } else if (name.endsWith(".md")) {
      acc.push(full);
    }
  }
  return acc;
}

// asset basenames (non-.md files: images, pdfs, …) so Obsidian embeds like
// ![[diagram.png]] — which resolve by basename against attachments — aren't misread
// as broken NOTE links. Same walk discipline as walk(): skip symlinks + IGNORE_DIRS.
function walkAssets(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const st = lstatSync(full);
    if (st.isSymbolicLink()) continue;
    if (st.isDirectory()) {
      if (!IGNORE_DIRS.has(name)) walkAssets(full, acc);
    } else if (!name.endsWith(".md")) {
      acc.push(name.toLowerCase());
    }
  }
  return acc;
}

const files = walk(ROOT);
const errors = [];
const warns = [];
const err = (rel, msg, fix) => errors.push({ rel, msg, fix });
const warn = (rel, msg, fix) => warns.push({ rel, msg, fix });

// index of every note id for wikilink resolution (relative-path + basename)
const noteIds = new Set();
for (const f of files) {
  const rel = relative(ROOT, f).replaceAll("\\", "/");
  noteIds.add(rel.replace(/\.md$/, "").toLowerCase());
  noteIds.add(basename(rel, ".md").toLowerCase());
}

// Two reference classes a vault legitimately uses but that live outside the .md note
// set — resolve them so the broken-link WARN flags only GENUINE breaks instead of
// drowning them in noise:
//
//  1. Agent-memory notes — an agent's per-project memory directory (Claude Code keeps
//     one at ~/.claude/projects/<slug>/memory/*.md). Vault notes [[link]] to these;
//     they are real notes, just outside the walked tree. Box-specific and existsSync-
//     guarded: on CI / another machine the dir is absent, so these correctly
//     re-surface there rather than silently passing.
//  2. Asset embeds — Obsidian ![[diagram.png]] embeds resolve by basename against
//     attachments; walkAssets indexes every non-.md vault file basename.
const memoryDir = join(homedir(), ".claude", "projects", ROOT.replaceAll("/", "-"), "memory");
if (existsSync(memoryDir)) {
  for (const name of readdirSync(memoryDir)) {
    if (name.endsWith(".md")) noteIds.add(basename(name, ".md").toLowerCase());
  }
}
for (const base of walkAssets(ROOT)) noteIds.add(base);

// folder -> set of note basenames linked from its index.md (for coverage hints)
const indexLinks = new Map();
for (const f of files) {
  const rel = relative(ROOT, f).replaceAll("\\", "/");
  if (!/(^|\/)index\.md$/.test(rel)) continue;
  const folder = rel.replace(/index\.md$/, "").replace(/\/$/, "");
  const set = new Set(findWikilinks(readFileSync(f, "utf8")).map((t) => basename(t).toLowerCase()));
  indexLinks.set(folder, set);
}

for (const f of files) {
  const rel = relative(ROOT, f).replaceAll("\\", "/");
  const text = readFileSync(f, "utf8");
  const lines = text.split("\n");

  // AGENTS.md must stay a short index, not an encyclopedia (a long rules file rots)
  if (rel === "AGENTS.md" && lines.length > AGENTS_MAX_LINES) {
    err(rel, `AGENTS.md is ${lines.length} lines (limit ${AGENTS_MAX_LINES})`,
      "It's a table of contents, not an encyclopedia. Move detail into docs/ and link to it.");
  }

  // every index / dashboard must have an H1 so the map has a title
  if ((/(^|\/)index\.md$/.test(rel) || rel.startsWith("dashboards/")) &&
      !lines.some((l) => /^#\s+\S/.test(l))) {
    err(rel, "missing an H1 heading", "Add a top-level '# Title' so the note has a clear entry point.");
  }

  // broken wikilink check (all notes except templates) — WARN, never blocks
  if (!skipWikilinks(rel)) {
    for (const target of findWikilinks(text)) {
      const key = target.replaceAll("\\", "/").toLowerCase().replace(/\.md$/, "");
      if (!noteIds.has(key) && !noteIds.has(basename(key))) {
        warn(rel, `broken wikilink [[${target}]]`,
          "Create the target note, fix the spelling, or remove the link.");
      }
    }
  }

  // oversized note hint (taste invariant). Exempt restore-source notes: a note that
  // embeds a live script verbatim as its restore source (a "## Script: `<path>`"
  // block — enforced byte-identical below) is legitimately large and CANNOT be split
  // without breaking that recovery contract. A standing expected warning would also
  // mask a future genuine oversize on the same file.
  const isRestoreSourceNote = /^##\s+Script:\s+`/m.test(text);
  if (!isExempt(rel) && !isRestoreSourceNote && lines.length > NOTE_SOFT_LINES) {
    warn(rel, `note is ${lines.length} lines (> ${NOTE_SOFT_LINES})`,
      "Consider splitting into focused notes and linking them.");
  }

  // ---- restore-source drift (WARN) ----
  // Convention: a "## Script: `<path>`" heading whose next fenced block is the
  // VERBATIM contents of a live, NON-git-tracked file (e.g. ~/.claude/hooks/*). That
  // embedded block IS the restore source — a machine rebuild or a lost ~/.claude
  // restores from the doc — so it must stay byte-identical to the live file. This is
  // the drift that silently rots hand-edited hooks. Only checked where the live file
  // exists (skipped on CI / another machine), and a WARN not an err() because it is
  // machine-specific and can't be a central gate — promote it to err() if you want it
  // to hard-block on the machine you edit from.
  for (const m of text.matchAll(/^##\s+Script:\s+`([^`]+)`[^\n]*\n(?:[ \t]*\n)*```[a-z-]*\n([\s\S]*?)\r?\n```/gm)) {
    const [, rawPath, block] = m;
    const livePath = rawPath.replace(/^(~|\$HOME)(?=\/)/, homedir());
    if (livePath.startsWith("/") && existsSync(livePath)) {
      const norm = (s) => s.replace(/\r\n/g, "\n").replace(/\n+$/, "");
      if (norm(readFileSync(livePath, "utf8")) !== norm(block)) {
        warn(rel, `restore-source drift: embedded \`${rawPath}\` block ≠ the live file`,
          `Reconcile them (the block is the restore source): copy the live ${rawPath} into the fenced block, or apply the doc's version to the live file, then re-run lint.`);
      }
    }
  }

  // ---- content-note frontmatter schema (ERRORs: block commits) ----
  if (isExempt(rel)) continue;
  const base = basename(rel, ".md");
  if (!isKebab(base)) {
    err(rel, `filename "${base}" is not kebab-case`,
      "Rename to lower-case-with-hyphens, e.g. harden-the-vps.md.");
  }
  const fm = parseFrontmatter(text);
  if (!fm) {
    err(rel, "missing or malformed YAML frontmatter",
      "Add a '---' frontmatter block. Copy the shape from templates/ or harness/schema.md.");
    continue;
  }
  for (const k of REQUIRED) {
    if (!(k in fm)) err(rel, `frontmatter missing '${k}'`, `Add '${k}:' — see harness/schema.md.`);
  }
  if (fm.type && !TYPES.includes(fm.type)) {
    err(rel, `invalid type '${fm.type}'`, `Use one of: ${TYPES.join(", ")}.`);
  }
  if (fm.status && !STATUSES.includes(fm.status)) {
    err(rel, `invalid status '${fm.status}'`, `Use one of: ${STATUSES.join(", ")}.`);
  }
  if (fm.created && !isoDate(fm.created)) err(rel, `'created' is not YYYY-MM-DD`, "Use an ISO date, e.g. 2026-06-08.");
  if (fm.updated && !isoDate(fm.updated)) err(rel, `'updated' is not YYYY-MM-DD`, "Use an ISO date, e.g. 2026-06-08.");
  if (isoDate(fm.created) && isoDate(fm.updated) && fm.updated < fm.created) {
    err(rel, "'updated' is before 'created'", "Bump 'updated' to the date you last touched the note.");
  }
  // projects must carry an overwrite-in-place "## Current state" section so a fresh
  // session reads one section instead of replaying the whole Timeline
  // (convention: docs/conventions.md).
  if (fm.type === "project" && !lines.some((l) => /^##\s+Current state\s*$/i.test(l))) {
    err(rel, "project note has no '## Current state' section",
      "Add '## Current state' (first line 'As of YYYY-MM-DD'; overwrite in place — history stays in Timeline).");
  }

  // ---- coverage + freshness (WARNs / garden) ----
  // Covered if linked from the nearest index.md in this folder or any ancestor,
  // so notes under projects/active/ still count against projects/index.md.
  let folder = rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "";
  let hasIndex = false, covered = false;
  for (;;) {
    if (indexLinks.has(folder)) {
      hasIndex = true;
      if (indexLinks.get(folder).has(base.toLowerCase())) { covered = true; break; }
    }
    if (folder === "") break;
    folder = folder.includes("/") ? folder.slice(0, folder.lastIndexOf("/")) : "";
  }
  if (hasIndex && !covered) {
    warn(rel, "not linked from a folder index.md",
      `Add a '[[${base}]]' link to the nearest index.md so the catalog stays complete.`);
  }
  if (GARDEN && isoDate(fm.updated) && fm.status !== "archived" && fm.status !== "done") {
    const ageDays = Math.floor((Date.parse(`${todayISO()}T00:00:00Z`) - Date.parse(`${fm.updated}T00:00:00Z`)) / 86400000);
    if (ageDays > STALE_DAYS) {
      warn(rel, `not updated in ${ageDays} days (status: ${fm.status})`,
        "Garden it: refresh the note, or set status to done/archived/blocked.");
    }
  }
}

// today's date without touching wall-clock at import time (garden mode only)
function todayISO() {
  const d = new Date();
  return d.toISOString().slice(0, 10);
}

// --- report ----------------------------------------------------------------
const fmtList = (items, glyph) => items.map((i) => `  ${glyph} ${i.rel}: ${i.msg}\n     ↳ ${i.fix}`).join("\n");

console.log(`personal-os lint — ${files.length} notes checked`);
if (warns.length) console.log(`\nwarnings (${warns.length}):\n${fmtList(warns, "•")}`);
if (errors.length) {
  console.log(`\nerrors (${errors.length}):\n${fmtList(errors, "✗")}`);
  console.log(`\n✗ verify failed — fix the ${errors.length} error(s) above.`);
  process.exit(1);
}
console.log(`\n✓ verify passed${warns.length ? ` (${warns.length} warning(s))` : ""}.`);
