---
name: telegram-export-mining
description: Use when answering a question from a downloaded Telegram chat/channel export — a `ChatExport_*` folder of `messages*.html` in ~/Downloads/Telegram Desktop, or any request to search/scrape/mine/summarize a Telegram history, find what a chat said about some topic, or pull knowledge out of a group's archive. Covers the `tools/tg-export` parser (HTML → JSONL), the map-then-read search discipline that keeps a 40k-message corpus inside a token budget, the five HTML traps that make naive scrapers lose data silently, and how to synthesize a cited answer without laundering chat folklore into fact.
---

# Mining a Telegram export

The tool is `tools/tg-export/tg_export.py` (zero-dep Python, full docs in
`tools/tg-export/README.md`). **Never** read `messages*.html` directly and never
write a throwaway parser — a 40-file export is ~32 MB of markup and every naive
scraper silently loses data (see *Traps*).

## The pipeline

```sh
T=tools/tg-export/tg_export.py
D=~/Downloads/"Telegram Desktop"/ChatExport_foo_2026-07-26

python3 $T parse "$D" -o /tmp/foo.jsonl     # ~3 s for 40k messages
python3 $T stats /tmp/foo.jsonl             # ALWAYS do this before planning
```

`stats` tells you what you're dealing with before you spend a token on it: date
range, author count, message volume. **It is also the parse check** — `no id` and
`empty author` must be `0`, and `media` must contain no `unknown`. Anything else
means the export has a shape the parser hasn't seen; fix the parser (and add a
test) rather than working around it downstream.

## Map, then read — the token discipline

The mistake is dumping matches straight into context. Three steps instead:

```sh
python3 $T search /tmp/foo.jsonl -e 'stripe|страйп' --count           # is there signal at all?
python3 $T search /tmp/foo.jsonl -e 'stripe|страйп' --clusters-only   # ~1 line per cluster
python3 $T search /tmp/foo.jsonl -e 'stripe|страйп' -C 12 --limit 5   # read only what matters
python3 $T window /tmp/foo.jsonl --start 12800 --end 12900            # close reading
python3 $T thread /tmp/foo.jsonl --id 12835                           # who answered whom
```

A 200-hit query maps to ~20 lines with `--clusters-only`; the same query with
`-C 10` is thousands. Cluster first, pick, then read. `search` merges overlapping
context windows into one cluster and pulls in replied-to parents that fell
outside the window, so a cluster reads as a conversation rather than fragments.

**Search both scripts, always.** Russian chats mix Cyrillic, transliteration and
English for the same concept: `stripe|страйп|страйп`, `llc|ллс|ооо`,
`kyc|верификац`. A single-script regex will quietly under-report.

## Fanning out to subagents

Give each subagent **one search angle**, the CLI usage above, the corpus path, and
these rules. Have it return structured findings — `{claim, ids[], quote_ru,
evidence_class, actionability}` — never prose.

Two non-negotiables, because both failure modes are common:

1. **Every claim carries message ids**, and a separate cheap verifier
   (`haiku` is enough) re-reads `window --start N-4 --end N+4` and confirms the
   messages actually say it. Agents paraphrase-as-verbatim and cite ids they
   never opened.
2. **Classify evidence**: `firsthand` ("I did this, it worked") /
   `secondhand` / `speculation` / `failure_report`. A group chat is mostly
   confident hearsay. Losing this distinction is how folklore becomes advice.

Tell each agent that *"my angle found little"* is a correct and useful answer.
Otherwise thin angles get padded with invention.

## Synthesizing

Keep three things visibly separate in the output:

- **What the chat says** — cited `[msg N]`, with the evidence class carried through.
- **What the chat doesn't cover** — collect each angle's coverage note. On a
  narrow topic this is often the most valuable part of the answer.
- **Current external truth** — a chat spanning years contains stale specifics
  (prices, "X is still available", policies). Verify anything time-sensitive
  against primary sources and cite URLs.

The corpus is evidence of *what a group believed*, not of what is true.

## Traps (already handled — don't reintroduce them)

| Trap | Silent failure |
|---|---|
| `...clearfix joined` | no `from_name`; author must carry forward |
| nested `forwarded body` | forwarded channel steals the message author |
| multi-part forwards | provenance lost on parts 2..n |
| cross-file replies | `href="messages9.html#go_to_message123"` has no `onclick` → replies dropped |
| `photo_wrap clearfix pull_left` | inline photos have no `media_<kind>` token → most media unclassified |

The way these were found, and the way to validate any future change: reconcile
parser output against raw `grep -c` counts on the real export (recipe in
`tools/tg-export/README.md` § *Verifying a parse*). Counts must match **exactly** —
"close enough" is how 227 missing replies hid.

Regression tests: `python3 tools/tg-export/tests/test_parse.py` (22 tests, one per
trap). Run them after touching the parser.

## Privacy

An export is personal data — real names, phone numbers, private chat. Keep the
JSONL in the scratchpad, not in the vault, and quote only what the answer needs.
When a finding lands in a vault note, cite the message id and the minimum quote;
don't copy whole conversations in.
