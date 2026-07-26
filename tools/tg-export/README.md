# tg-export — mine a Telegram Desktop HTML export

Turns `Telegram Desktop → Export chat history → HTML` into greppable JSONL, then
lets you search it with conversation context instead of scrolling 40 MB of HTML.

Zero dependencies (stdlib Python 3.8+), so it keeps working anywhere.

```sh
T=tools/tg-export/tg_export.py

# 1. HTML → JSONL (41 files / 40k messages ≈ 3 s)
python3 $T parse ~/Downloads/"Telegram Desktop"/ChatExport_foo -o /tmp/foo.jsonl

# 2. shape of the corpus before you spend tokens on it
python3 $T stats /tmp/foo.jsonl

# 3. map cheaply, then read deeply
python3 $T search /tmp/foo.jsonl -e 'stripe|страйп' --count
python3 $T search /tmp/foo.jsonl -e 'stripe|страйп' --clusters-only   # one line per cluster
python3 $T search /tmp/foo.jsonl -e 'stripe|страйп' -C 12 --limit 5   # with context
python3 $T search /tmp/foo.jsonl -e 'llc' -e 'delaware' --since 2025-01-01 --author Alex
python3 $T window /tmp/foo.jsonl --start 12800 --end 12900            # read a range in full
python3 $T thread /tmp/foo.jsonl --id 12835                           # reply tree
python3 $T search /tmp/foo.jsonl -e 'atlas' --format json             # pipe to jq
```

`--clusters-only` exists so an agent can map a 200-hit query for ~20 lines of
output, pick the 5 clusters that matter, and only then pay for the full read.

## Record shape

```json
{"id": 12835, "ts": "2026-05-30T12:35:38", "date": "2026-05-30", "time": "12:35:38",
 "from": "Alex", "joined": true, "reply_to": 12832, "text": "…", "links": ["https://…"],
 "media": {"kind": "photo", "title": "…", "status": "01:00, 21.4 MB"},
 "forwarded": true, "forwarded_from": "SomeChannel", "forwarded_reply_to": 555,
 "reply_to_external": true, "file": "messages13.html"}
```

Only `id`, `ts`, `date`, `time`, `from`, `joined`, `reply_to`, `text`, `links`,
`file` are always present; the rest appear when they apply. Service messages get
`{"service": true, "action": "…"}`.

## The five HTML traps (all handled, all regression-tested)

Telegram's HTML is machine-generated and stable, but naive scrapers lose data
silently. Each of these was found by reconciling parser output against raw
`grep -c` counts on a real 40,055-message export:

| Trap | What a naive parser does | Reality |
|---|---|---|
| `message default clearfix joined` | leaves `from` empty | consecutive message from the same author; **no** `from_name` — carry it forward |
| nested `<div class="forwarded body">` | attributes the *forwarded channel* as the message author | outer `body` owns author+date; inner owns text+media. Prune the subtree (`stop_cls`) |
| multi-part forwards (albums) | drops provenance on parts 2..n | only part 1 prints `from_name` — carry it, reset on the next normal message |
| cross-file replies | drops them (227/18498 here) | same-file replies use `onclick="GoToMessage(123)"`; **cross-file uses only `href="messages9.html#go_to_message123"`** |
| `photo_wrap clearfix pull_left` | `kind: unknown` for the *majority* of media | inline photos have no `media_<kind>` token — match class *tokens*, not the exact attribute |

Two more that are semantics, not bugs:

- **"In reply to a message in another chat"** has no resolvable id → `reply_to_external: true`
  rather than a silently missing reply.
- A **forward that was itself a reply** links to an id in its *source* chat, which
  would resolve to an unrelated message here → kept as `forwarded_reply_to`.

Timestamps come from the `title=` attribute (`"04.01.2021 18:53:16 UTC+03:00"`),
not the visible `18:53`; the calendar dividers (`8 December 2020`) are parser
state, not content, and are the only way to date a message whose title is absent.

## Verifying a parse

The discipline that found every bug above — reconcile against the raw HTML:

```sh
D=~/Downloads/"Telegram Desktop"/ChatExport_foo
grep -o 'class="message default clearfix' $D/messages*.html | wc -l   # == stats "chat"
grep -o 'class="reply_to details"'          $D/messages*.html | wc -l   # == replies + external + forwarded_reply_to
grep -o 'class="forwarded body"'            $D/messages*.html | wc -l   # == forwards
```

`stats` also prints `no id` and `empty author` — both must be **0**, and `media`
must contain no `unknown`.

## Tests

```sh
python3 tools/tg-export/tests/test_parse.py    # 22 tests, one per trap
```

The fixture in `tests/test_parse.py` reproduces all five traps, so a future
refactor that reintroduces one fails immediately.
