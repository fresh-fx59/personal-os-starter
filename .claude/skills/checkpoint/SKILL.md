---
name: checkpoint
description: Use when the context statusline nudges you, before running /clear, or when switching to an unrelated task or repository — to presave the session's durable state into the vault so context can be cleared without losing progress.
---

# Checkpoint

## Overview

Before you `/clear`, save the session's durable state into the vault as a versioned note, so
continuity lives in the note — not in a 500K-token transcript. Then `/clear` resets resident context to
~0 and the next task starts cheap.

The agent cannot run `/clear` from a skill, so this skill **presaves**; you type `/clear` after.

## When to use

- The statusline warns that resident context is large.
- About to switch to an unrelated task or repo.
- Any time before `/clear`, so nothing is lost.

## Procedure

1. **Find the active note** — the `projects/active/*.md` note matching the current work (by cwd, files
   touched, topic). If none fits, copy `templates/project.md` to a new `projects/active/<kebab>.md`.
2. **Overwrite `## Current state` in place** with current truth ONLY: what's done, what's in flight, the
   **exact next step**, key commit SHAs / PR numbers / paths / commands / decisions, and open questions.
   Current-truth only — move anything historical to `## Timeline` (add a dated line).
3. **Lint** — from the vault root (the directory with `AGENTS.md` + `package.json`) run `npm run lint`
   and fix every `✗`.
4. **Confirm the save** — obsidian-git auto-commits and pushes; confirm it committed.
5. **Record the pointer** so the fresh session auto-reloads — write the note's absolute path to
   `~/.claude/last-checkpoint` (single line, overwrite).
6. **Report + hand off** — "✅ Checkpointed to `<note>`. Safe to `/clear` — the fresh session
   auto-reloads this note." Then tell the human to type `/clear`.

## What good looks like

Someone reading only the note's `## Current state` can resume with **zero** access to this transcript.
No raw dumps — link to files and commits, and state the next action explicitly.

## Why not just compact the conversation

Compaction produces a lossy summary that still lives *in the transcript*: it dies with the session, it
isn't reviewable or correctable, the next agent can't read it, and each successive compaction degrades
the last. A checkpoint is a **file in git** — diffable, editable, and durable. It is the prime directive
applied to your own context: if it isn't written into the repo, it doesn't exist.

Compaction is still right mid-task, when you want to continue in the *same* thread and the state isn't
coherent enough to write down yet. Checkpoint at boundaries; compact within one.

## The restore half

`../../hooks/checkpoint-restore.sh` is a `SessionStart` hook matching `clear`. It reads the pointer,
extracts just the note's `## Current state` section, and injects it into the fresh session — so the new
session starts near-zero context but already knows the exact next step. It emits nothing unless the
source really is `clear` **and** a valid note with that section exists; any failure exits silently.

Wire it up via `.claude/settings.json.example`.

## Common mistakes

- Writing history into Current state (it is overwrite-in-place current-truth; history → Timeline).
- Skipping step 5 (the pointer) — the restore hook then has nothing to reload.
- Clearing before the note is committed.
