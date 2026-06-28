# Frontmatter schema

Every **content note** — anything in `projects/`, `incidents/`, `areas/`,
`references/`, or `decisions/` that isn't an `index.md` — starts with a YAML
frontmatter block. The linter (`lint-notes.mjs`) enforces it. Meta docs,
templates, dashboards, and index files are exempt.

```yaml
---
title: Human-readable title of the note
type: incident          # project | incident | decision | reference | area | dashboard
status: active          # idea | active | blocked | done | archived
created: 2026-06-08      # ISO date, YYYY-MM-DD
updated: 2026-06-08      # ISO date; must be >= created
tags: [security, infra]  # optional inline array
links: ["[[areas/the-vps]]"]  # optional related notes
---
```

## Rules — errors (these fail `npm run lint`)

- Frontmatter block present and parseable.
- Required keys: `title`, `type`, `status`, `created`, `updated`.
- `type` and `status` are from the allowed sets above.
- `created` / `updated` are `YYYY-MM-DD`; `updated` is not before `created`.
- Filename is `kebab-case.md`.

## Hints — warnings (never block)

- Broken `[[wikilinks]]`.
- Note longer than 400 lines (consider splitting).
- Note not linked from its folder's `index.md`.
- With `--garden`: an active/idea/blocked note untouched for 180+ days.

To change these rules, edit `lint-notes.mjs` — here, the schema *is* the code.
