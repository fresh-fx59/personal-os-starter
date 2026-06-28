# Conventions

Detailed habits referenced from `AGENTS.md`. The frontmatter schema itself lives in
`harness/schema.md`; this file covers everything around it.

## Naming

- Content filenames are `kebab-case.md`: lowercase, words joined by hyphens. The
  linter enforces this. Example: `harden-the-vps.md`.
- Decision records are numbered: `NNNN-short-title.md`, e.g.
  `0001-personal-os-harness.md`.
- Folder catalogs are always `index.md`.

## Frontmatter

See `harness/schema.md` for the schema. Always set `status` honestly and bump
`updated` whenever you touch a note.

### status meanings

- `idea` — captured, not started.
- `active` — being worked now.
- `blocked` — waiting on a human or an external thing; say what, in the body.
- `done` — finished; no further work expected.
- `archived` — kept for the record, no longer relevant.

## Linking

- Relate notes with Obsidian wikilinks: `[[note-name]]` or `[[folder/note-name]]`.
- Link every new note from its folder's `index.md` so the catalog stays complete.
- Use the full `[[folder/note]]` form when a basename would be ambiguous.
- In docs and templates, write example links inside backticks so the linter does
  not treat them as real (and therefore broken) links.

## Note structure

- Open with an H1 that matches the `title`.
- **Projects and incidents** keep two running sections, treated as first-class
  artifacts:
  - **Timeline** — dated entries of what happened or what was done.
  - **Decision log** — each meaningful choice, the options weighed, and why.
  - Scale the ceremony to the work: a small change needs only a Timeline line, while
    complex work keeps a full Decision log.
- Record unknowns under `## Open questions` instead of guessing silently.

## Verifying

Run `npm run lint` before you call a note done; fix every `✗`. The pre-commit hook
runs the same check **advisorily** — it never blocks your obsidian-git backup.
Warnings (`•`) are for the gardener, not blockers.
