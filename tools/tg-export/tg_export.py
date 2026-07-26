#!/usr/bin/env python3
"""tg-export — turn a Telegram Desktop HTML export into greppable JSONL.

Telegram Desktop's "Export chat history → HTML" writes `messages*.html` files of
~1000 messages each. That format is machine-generated and stable, but three
things trip up naive scrapers, so they are handled here once:

  1. `<div class="message default clearfix joined">` — a consecutive message
     from the same author. It has NO `from_name`; the author must be carried
     forward from the previous non-joined message.
  2. `<div class="forwarded body">` — a nested block with its OWN `from_name`
     and `text`. A flat regex attributes the forwarded author to the message.
  3. Dates live in the `title=` attribute of the date div ("04.01.2021 18:53:16
     UTC+03:00"), not in its visible text ("18:53"). Service dividers ("8
     December 2020") are the only visible calendar markers.

Stdlib only, on purpose: this must keep working on any machine years from now.

Subcommands
-----------
  parse   <export-dir>  -o corpus.jsonl     HTML → JSONL (one message per line)
  search  <corpus.jsonl> -e REGEX ...       find messages, with context/threads
  thread  <corpus.jsonl> --id N             reconstruct one reply chain
  window  <corpus.jsonl> --from N --to M    dump a contiguous id range
  stats   <corpus.jsonl>                    corpus shape: dates, authors, volume

Message record (JSONL):
  id, ts, date, time, from, joined, reply_to, text, links[], media{}, edited,
  forwarded_from, service, action, file
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
from collections import Counter
from html.parser import HTMLParser

# ---------------------------------------------------------------- mini DOM ---

VOID = {"br", "img", "hr", "input", "meta", "link", "source"}


class Node:
    __slots__ = ("tag", "cls", "attrs", "kids", "parent")

    def __init__(self, tag: str, attrs: dict, parent: "Node | None"):
        self.tag = tag
        self.attrs = attrs
        self.cls = attrs.get("class", "")
        self.kids: list = []  # Node | str
        self.parent = parent

    def find(self, cls: str, *, deep: bool = True, stop_cls: str | None = None):
        """First descendant whose class attribute equals `cls`.

        `stop_cls` prunes whole subtrees — that is how the outer message keeps
        its own author when a `forwarded body` sits inside it.
        """
        for kid in self.kids:
            if not isinstance(kid, Node):
                continue
            if stop_cls and kid.cls == stop_cls:
                continue
            if kid.cls == cls:
                return kid
            if deep:
                got = kid.find(cls, deep=True, stop_cls=stop_cls)
                if got is not None:
                    return got
        return None

    def has(self, token: str) -> bool:
        """Class-token test. Telegram mixes layout classes into the same
        attribute ("photo_wrap clearfix pull_left", "block_link media_photo"),
        so exact-string matching silently misses the majority of media."""
        return token in self.cls.split()

    def find_token(self, token: str, *, stop_cls: str | None = None):
        for kid in self.kids:
            if not isinstance(kid, Node):
                continue
            if stop_cls and kid.cls == stop_cls:
                continue
            if kid.has(token):
                return kid
            got = kid.find_token(token, stop_cls=stop_cls)
            if got is not None:
                return got
        return None

    def find_all(self, pred, *, out=None):
        out = [] if out is None else out
        for kid in self.kids:
            if isinstance(kid, Node):
                if pred(kid):
                    out.append(kid)
                kid.find_all(pred, out=out)
        return out


class DomBuilder(HTMLParser):
    """Builds a tree of only the tags we care about; text is kept inline."""

    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.root = Node("root", {}, None)
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if tag in VOID:
            if tag == "br":
                self.cur.kids.append("\n")
            elif tag == "img":
                # custom emoji / stickers degrade to their alt text
                alt = a.get("alt")
                if alt:
                    self.cur.kids.append(alt)
            return
        node = Node(tag, a, self.cur)
        self.cur.kids.append(node)
        self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)  # void-tag path returns without descending

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        node = self.cur
        while node is not self.root and node.tag != tag:
            node = node.parent  # tolerate unclosed tags
        if node is not self.root:
            self.cur = node.parent or self.root

    def handle_data(self, data):
        self.cur.kids.append(data)

    def handle_entityref(self, name):
        self.cur.kids.append(html.unescape(f"&{name};"))

    def handle_charref(self, name):
        self.cur.kids.append(html.unescape(f"&#{name};"))


def text_of(node: Node | None, *, stop_cls: str | None = None) -> str:
    """Flatten a subtree to text, pruning `stop_cls` subtrees."""
    if node is None:
        return ""
    buf: list[str] = []

    def walk(n: Node):
        for kid in n.kids:
            if isinstance(kid, str):
                buf.append(kid)
            elif stop_cls and kid.cls == stop_cls:
                continue
            else:
                walk(kid)

    walk(node)
    return re.sub(r"[ \t]+\n", "\n", "".join(buf)).strip()


# ----------------------------------------------------------------- parsing ---

MONTHS = {
    m: i + 1
    for i, m in enumerate(
        "January February March April May June July August September October "
        "November December".split()
    )
}
TS_RE = re.compile(r"(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}:\d{2}:\d{2})")
DIVIDER_RE = re.compile(r"^(\d{1,2})\s+([A-Z][a-z]+)\s+(\d{4})$")


def _ts(title: str) -> tuple[str, str, str]:
    """'04.01.2021 18:53:16 UTC+03:00' → (iso, date, time)."""
    m = TS_RE.search(title or "")
    if not m:
        return "", "", ""
    dd, mm, yyyy, hhmmss = m.groups()
    return f"{yyyy}-{mm}-{dd}T{hhmmss}", f"{yyyy}-{mm}-{dd}", hhmmss


def _media(body: Node) -> dict:
    """Media placeholder → {kind, title, description, status}.

    Two unrelated shapes: attachments carry a `media_<kind>` token, while inline
    photos are a bare `<a class="photo_wrap clearfix pull_left">` — the most
    common media in a real chat, and the one an exact-class match loses.
    """
    wrap = body.find_token("media_wrap")
    if wrap is None:
        return {}
    kind = ""
    holder = wrap.find_all(
        lambda n: any(t.startswith("media_") for t in n.cls.split()))
    for node in holder:
        tok = next(t for t in node.cls.split() if t.startswith("media_"))
        if tok != "media_wrap":
            kind = tok[len("media_"):]
            break
    if not kind and wrap.find_token("photo_wrap") is not None:
        kind = "photo"
    out = {"kind": kind or "unknown"}
    for key, cls in (("title", "title bold"), ("description", "description"),
                     ("status", "status details")):
        val = text_of(wrap.find(cls))
        if val:
            out[key] = val
    a = wrap.find_all(lambda n: n.tag == "a" and n.attrs.get("href"))
    if a:
        out["href"] = a[0].attrs["href"]
    return out


def _links(node: Node | None) -> list[str]:
    if node is None:
        return []
    seen, out = set(), []
    for a in node.find_all(lambda n: n.tag == "a"):
        href = a.attrs.get("href", "")
        if href.startswith(("http://", "https://", "tg://")) and href not in seen:
            seen.add(href)
            out.append(href)
    return out


# Same-file replies carry onclick="GoToMessage(123)"; replies whose parent lives
# in an EARLIER messages*.html carry only href="messages9.html#go_to_message123".
# Matching just the first form loses every cross-file reply (227 of 18498 here).
REPLY_RE = re.compile(r"(?:GoToMessage\((\d+)\)|#go_to_message(\d+))")


def parse_file(path: str, carry: dict) -> list[dict]:
    """Parse one messages*.html. `carry` threads author/date state across files."""
    with open(path, encoding="utf-8") as fh:
        dom = DomBuilder()
        dom.feed(fh.read())

    msgs: list[dict] = []
    fname = os.path.basename(path)
    blocks = dom.root.find_all(lambda n: n.cls.startswith("message "))

    for blk in blocks:
        mid = blk.attrs.get("id", "")
        num = int(mid[7:]) if mid.startswith("message") and mid[7:].lstrip("-").isdigit() else None

        if "service" in blk.cls:
            body = text_of(blk.find("body details"))
            dm = DIVIDER_RE.match(body)
            if dm:  # calendar divider — pure state, not content
                d, mon, y = dm.groups()
                if mon in MONTHS:
                    carry["date"] = f"{y}-{MONTHS[mon]:02d}-{int(d):02d}"
                continue
            msgs.append({
                "id": num, "ts": "", "date": carry.get("date", ""), "time": "",
                "from": "", "service": True, "action": body, "text": body,
                "file": fname,
            })
            continue

        body = blk.find("body", deep=False)
        if body is None:
            continue
        joined = "joined" in blk.cls

        # Prune the forwarded subtree so the OUTER author/date win.
        author = text_of(body.find("from_name", stop_cls="forwarded body"))
        if author:
            carry["from"] = author
        elif joined:
            author = carry.get("from", "")

        date_div = body.find("pull_right date details", stop_cls="forwarded body")
        ts, date, time = _ts(date_div.attrs.get("title", "") if date_div else "")
        if date:
            carry["date"] = date

        # A multi-part forward (album, or several parts of one forwarded post)
        # repeats `forwarded body` but prints from_name only on the first part.
        # Carry the source across those continuations so provenance is never lost.
        fwd_body = body.find("forwarded body")
        fwd_from = ""
        if fwd_body is not None:
            fwd_name = fwd_body.find("from_name")
            fwd_from = text_of(fwd_name)
            # the nested "<span class=date details>" tail is part of that name
            fwd_from = re.sub(r"\s*\d{2}\.\d{2}\.\d{4}\s+\d{2}:\d{2}:\d{2}\s*$", "", fwd_from).strip()
            if fwd_from:
                carry["fwd"] = fwd_from
            else:
                fwd_from = carry.get("fwd", "")
        else:
            carry.pop("fwd", None)

        src = fwd_body if fwd_body is not None else body
        text = text_of(src.find("text"))
        media = _media(src)

        def reply_id(div: Node | None):
            """(id, external) — 'In reply to a message in another chat' has no id."""
            if div is None:
                return None, False
            for a in div.find_all(lambda n: n.tag == "a"):
                m = REPLY_RE.search(a.attrs.get("onclick", "") + " " + a.attrs.get("href", ""))
                if m:
                    return int(m.group(1) or m.group(2)), False
            return None, True

        reply_to, reply_external = reply_id(
            body.find("reply_to details", stop_cls="forwarded body"))
        # A forward can itself have been a reply in its SOURCE chat; that id does
        # not resolve in this corpus, so keep it in a separate field.
        fwd_reply_to = None
        if fwd_body is not None:
            fwd_reply_to, _ = reply_id(fwd_body.find("reply_to details"))

        edited = body.find("date details")
        edited_txt = ""
        if edited is not None and "Edited" in text_of(edited):
            edited_txt = text_of(edited)

        rec = {
            "id": num,
            "ts": ts,
            "date": date or carry.get("date", ""),
            "time": time,
            "from": author or carry.get("from", ""),
            "joined": joined,
            "reply_to": reply_to,
            "text": text,
            "links": _links(src.find("text")) + _links(src.find("media_wrap clearfix")),
            "file": fname,
        }
        if media:
            rec["media"] = media
        if fwd_body is not None:
            rec["forwarded"] = True
        if fwd_from:
            rec["forwarded_from"] = fwd_from
        if fwd_reply_to is not None:
            rec["forwarded_reply_to"] = fwd_reply_to
        if reply_external:
            rec["reply_to_external"] = True
        if edited_txt:
            rec["edited"] = edited_txt
        msgs.append(rec)
    return msgs


def file_sort_key(name: str) -> int:
    m = re.search(r"messages(\d*)\.html$", name)
    if not m:
        return 1 << 30
    return int(m.group(1) or 1)


def cmd_parse(args) -> int:
    src = args.export_dir
    if os.path.isfile(src):
        files = [src]
    else:
        files = sorted(
            (os.path.join(src, f) for f in os.listdir(src)
             if re.fullmatch(r"messages\d*\.html", f)),
            key=file_sort_key,
        )
    if not files:
        print(f"tg-export: no messages*.html under {src}", file=sys.stderr)
        return 2

    out = open(args.out, "w", encoding="utf-8") if args.out else sys.stdout
    carry: dict = {}
    total = 0
    try:
        for path in files:
            got = parse_file(path, carry)
            for rec in got:
                out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            total += len(got)
            if args.out:
                print(f"  {os.path.basename(path):<18} {len(got):>5} messages",
                      file=sys.stderr)
    finally:
        if args.out:
            out.close()
    print(f"tg-export: {total} messages from {len(files)} file(s)"
          + (f" → {args.out}" if args.out else ""), file=sys.stderr)
    return 0


# ------------------------------------------------------------------ queries ---

def load(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def render(m: dict, *, mark: bool = False) -> str:
    head = f"[{m.get('id')}] {m.get('date','')} {m.get('time','')[:5]} {m.get('from','')}"
    if m.get("reply_to"):
        head += f" ↩{m['reply_to']}"
    if m.get("forwarded_from"):
        head += f" (fwd: {m['forwarded_from']})"
    if m.get("media"):
        head += f" [{m['media'].get('kind')}]"
    if m.get("service"):
        head += " (service)"
    body = (m.get("text") or "").replace("\n", "\n    ")
    return ("»" if mark else " ") + head + (f"\n    {body}" if body else "")


def cmd_search(args) -> int:
    msgs = load(args.corpus)
    by_id = {m["id"]: i for i, m in enumerate(msgs) if m.get("id") is not None}
    flags = 0 if args.case_sensitive else re.IGNORECASE
    pats = [re.compile(p, flags) for p in args.expr]

    hits = []
    for i, m in enumerate(msgs):
        blob = f"{m.get('text','')}\n{' '.join(m.get('links',[]))}"
        if any(p.search(blob) for p in pats):
            if args.since and m.get("date", "") < args.since:
                continue
            if args.until and m.get("date", "") > args.until:
                continue
            if args.author and args.author.lower() not in m.get("from", "").lower():
                continue
            hits.append(i)

    if args.count:
        print(len(hits))
        return 0

    if args.format == "json":
        sel = hits[: args.limit] if args.limit else hits
        print(json.dumps([msgs[i] for i in sel], ensure_ascii=False, indent=1))
        return 0

    # Group hits into clusters so an overlapping ±context reads as one thread.
    ctx = args.context
    spans: list[list[int]] = []
    for i in hits:
        lo, hi = max(0, i - ctx), min(len(msgs) - 1, i + ctx)
        if spans and lo <= spans[-1][1] + 1:
            spans[-1][1] = max(spans[-1][1], hi)
            spans[-1][2].append(i)  # type: ignore[union-attr]
        else:
            spans.append([lo, hi, [i]])  # type: ignore[list-item]

    if args.clusters_only:
        for lo, hi, hs in spans:
            print(f"{msgs[lo].get('date')} ids {msgs[lo].get('id')}..{msgs[hi].get('id')} "
                  f"({len(hs)} hit{'s' if len(hs)>1 else ''}, {hi-lo+1} msgs) {msgs[lo].get('file')}")
        print(f"# {len(hits)} hits in {len(spans)} clusters", file=sys.stderr)
        return 0

    shown = spans[: args.limit] if args.limit else spans
    for lo, hi, hs in shown:
        hset = set(hs)
        print(f"\n=== {msgs[lo].get('date')} · ids {msgs[lo].get('id')}–{msgs[hi].get('id')} "
              f"· {len(hs)} hit(s) · {msgs[lo].get('file')} ===")
        for i in range(lo, hi + 1):
            print(render(msgs[i], mark=i in hset))
        # pull in replied-to parents that fell outside the window
        for i in hs:
            rt = msgs[i].get("reply_to")
            if rt and not (lo <= by_id.get(rt, -1) <= hi) and rt in by_id:
                print(f"  ↳ parent of {msgs[i]['id']}:")
                print("  " + render(msgs[by_id[rt]]))
    print(f"\n# {len(hits)} hits in {len(spans)} clusters"
          + (f", showing {len(shown)}" if len(shown) != len(spans) else ""),
          file=sys.stderr)
    return 0


def cmd_thread(args) -> int:
    msgs = load(args.corpus)
    by_id = {m["id"]: m for m in msgs if m.get("id") is not None}
    kids: dict = {}
    for m in msgs:
        if m.get("reply_to"):
            kids.setdefault(m["reply_to"], []).append(m)

    root = by_id.get(args.id)
    if root is None:
        print(f"tg-export: no message {args.id}", file=sys.stderr)
        return 2
    while root.get("reply_to") and root["reply_to"] in by_id:  # climb to the root
        root = by_id[root["reply_to"]]

    def walk(m, depth=0):
        print("  " * depth + render(m, mark=m["id"] == args.id))
        for kid in sorted(kids.get(m["id"], []), key=lambda x: x.get("id") or 0):
            walk(kid, depth + 1)

    walk(root)
    return 0


def cmd_window(args) -> int:
    msgs = load(args.corpus)
    for m in msgs:
        mid = m.get("id")
        if mid is not None and args.start <= mid <= args.end:
            print(render(m))
    return 0


def cmd_stats(args) -> int:
    msgs = load(args.corpus)
    real = [m for m in msgs if not m.get("service")]
    dates = sorted(m["date"] for m in real if m.get("date"))
    authors = Counter(m.get("from", "?") for m in real)
    media = Counter(m["media"].get("kind") for m in real if m.get("media"))
    print(f"messages       : {len(msgs)} ({len(real)} chat, {len(msgs)-len(real)} service)")
    print(f"date range     : {dates[0]} → {dates[-1]}" if dates else "date range     : n/a")
    print(f"authors        : {len(authors)}")
    print(f"with links     : {sum(1 for m in real if m.get('links'))}")
    print(f"replies        : {sum(1 for m in real if m.get('reply_to'))}")
    print(f"forwards       : {sum(1 for m in real if m.get('forwarded_from'))}")
    print(f"media          : {dict(media)}")
    print(f"no id          : {sum(1 for m in msgs if m.get('id') is None)}")
    print(f"empty author   : {sum(1 for m in real if not m.get('from'))}")
    print("\ntop authors:")
    for name, n in authors.most_common(15):
        print(f"  {n:>6}  {name}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="tg-export", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("parse", help="HTML export dir → JSONL")
    p.add_argument("export_dir")
    p.add_argument("-o", "--out", help="output .jsonl (default: stdout)")
    p.set_defaults(fn=cmd_parse)

    p = sub.add_parser("search", help="regex search with conversation context")
    p.add_argument("corpus")
    p.add_argument("-e", "--expr", action="append", required=True,
                   help="regex (repeatable, OR-ed)")
    p.add_argument("-C", "--context", type=int, default=6,
                   help="messages of context each side (default 6)")
    p.add_argument("--limit", type=int, default=0, help="max clusters/records")
    p.add_argument("--since"), p.add_argument("--until")
    p.add_argument("--author")
    p.add_argument("--case-sensitive", action="store_true")
    p.add_argument("--count", action="store_true", help="print hit count only")
    p.add_argument("--clusters-only", action="store_true",
                   help="one line per cluster — cheap map before deep reads")
    p.add_argument("--format", choices=["text", "json"], default="text")
    p.set_defaults(fn=cmd_search)

    p = sub.add_parser("thread", help="reconstruct a reply tree")
    p.add_argument("corpus")
    p.add_argument("--id", type=int, required=True)
    p.set_defaults(fn=cmd_thread)

    p = sub.add_parser("window", help="dump a contiguous id range")
    p.add_argument("corpus")
    p.add_argument("--start", type=int, required=True)
    p.add_argument("--end", type=int, required=True)
    p.set_defaults(fn=cmd_window)

    p = sub.add_parser("stats", help="corpus shape")
    p.add_argument("corpus")
    p.set_defaults(fn=cmd_stats)

    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
