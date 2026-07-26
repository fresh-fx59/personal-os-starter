#!/usr/bin/env python3
"""Tests for tg_export — one per HTML quirk that burned us on the real export.

Run: python3 tools/tg-export/tests/test_parse.py
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(os.path.dirname(HERE), "tg_export.py")
sys.path.insert(0, os.path.dirname(HERE))

import tg_export  # noqa: E402

FIXTURE = """<!DOCTYPE html><html><head><meta charset="utf-8"/></head><body>
<div class="page_wrap"><div class="page_body chat_page"><div class="history">

 <div class="message service" id="message-1">
  <div class="body details">
8 December 2020
  </div>
 </div>

 <div class="message service" id="message1">
  <div class="body details">
Channel &laquo;Test&raquo; created
  </div>
 </div>

 <div class="message default clearfix" id="message2">
  <div class="body">
   <div class="pull_right date details" title="08.12.2020 03:41:07 UTC+03:00">
03:41
   </div>
   <div class="from_name">
Alice
   </div>
   <div class="text">
first<br>second &amp; third
   </div>
  </div>
 </div>

 <div class="message default clearfix joined" id="message3">
  <div class="body">
   <div class="pull_right date details" title="08.12.2020 03:42:00 UTC+03:00">
03:42
   </div>
   <div class="text">
joined message, author must be carried
   </div>
  </div>
 </div>

 <div class="message default clearfix" id="message4">
  <div class="body">
   <div class="pull_right date details" title="08.12.2020 03:43:00 UTC+03:00">
03:43
   </div>
   <div class="from_name">
Bob
   </div>
   <div class="reply_to details">
In reply to <a href="#go_to_message2" onclick="return GoToMessage(2)">this message</a>
   </div>
   <div class="text">
see <a href="https://stripe.com/atlas">https://stripe.com/atlas</a>
   </div>
  </div>
 </div>

 <div class="message default clearfix" id="message5">
  <div class="body">
   <div class="pull_right date details" title="08.12.2020 03:44:00 UTC+03:00">
03:44
   </div>
   <div class="from_name">
Bob
   </div>
   <div class="reply_to details">
In reply to <a href="messages1.html#go_to_message999">this message</a>
   </div>
   <div class="text">
cross-file reply, no onclick
   </div>
  </div>
 </div>

 <div class="message default clearfix" id="message6">
  <div class="body">
   <div class="pull_right date details" title="08.12.2020 03:45:00 UTC+03:00">
03:45
   </div>
   <div class="from_name">
Carol
   </div>
   <div class="reply_to details">
In reply to a message in another chat
   </div>
   <div class="text">
external reply, no id exists
   </div>
  </div>
 </div>

 <div class="message default clearfix" id="message7">
  <div class="body">
   <div class="pull_right date details" title="08.12.2020 03:46:00 UTC+03:00">
03:46
   </div>
   <div class="from_name">
Dave
   </div>
   <div class="pull_left forwarded userpic_wrap">
    <div class="userpic userpic5"><div class="initials">C</div></div>
   </div>
   <div class="forwarded body">
    <div class="from_name">
SomeChannel <span class="date details" title="08.12.2020 03:40:00 UTC+03:00"> 08.12.2020 03:40:00</span>
    </div>
    <div class="reply_to details">
In reply to <a href="#go_to_message555" onclick="return GoToMessage(555)">this message</a>
    </div>
    <div class="media_wrap clearfix">
     <div class="media clearfix pull_left media_video">
      <div class="body">
       <div class="title bold">
Video file
       </div>
       <div class="description">
Not included, change data exporting settings to download.
       </div>
       <div class="status details">
01:00, 21.4 MB
       </div>
      </div>
     </div>
    </div>
    <div class="text">
forwarded text body
    </div>
   </div>
  </div>
 </div>

 <div class="message default clearfix joined" id="message8">
  <div class="body">
   <div class="pull_right date details" title="08.12.2020 03:47:00 UTC+03:00">
03:47
   </div>
   <div class="forwarded body">
    <div class="media_wrap clearfix">
     <a class="photo_wrap clearfix pull_left" href="photos/photo_1.jpg">
      <img class="photo" src="photos/photo_1_thumb.jpg"/>
     </a>
    </div>
   </div>
  </div>
 </div>

 <div class="message service" id="message-2">
  <div class="body details">
9 December 2020
  </div>
 </div>

 <div class="message default clearfix" id="message9">
  <div class="body">
   <div class="pull_right date details" title="09.12.2020 10:00:00 UTC+03:00">
10:00
   </div>
   <div class="from_name">
Alice
   </div>
   <div class="text">
next day
   </div>
  </div>
 </div>

</div></div></div></body></html>
"""


class ParseTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        with open(os.path.join(cls.tmp, "messages.html"), "w", encoding="utf-8") as fh:
            fh.write(FIXTURE)
        cls.msgs = tg_export.parse_file(os.path.join(cls.tmp, "messages.html"), {})
        cls.by_id = {m["id"]: m for m in cls.msgs}

    def test_calendar_divider_is_state_not_content(self):
        # the "8 December 2020" divider must not appear as a message …
        self.assertNotIn("8 December 2020", [m["text"] for m in self.msgs])
        # … but the real service message survives
        self.assertTrue(any(m.get("service") and "created" in m["text"] for m in self.msgs))

    def test_divider_sets_date_for_messages(self):
        self.assertEqual(self.by_id[2]["date"], "2020-12-08")
        self.assertEqual(self.by_id[9]["date"], "2020-12-09")

    def test_timestamp_from_title_attribute(self):
        self.assertEqual(self.by_id[2]["ts"], "2020-12-08T03:41:07")
        self.assertEqual(self.by_id[2]["time"], "03:41:07")

    def test_br_becomes_newline_and_entities_unescaped(self):
        self.assertEqual(self.by_id[2]["text"], "first\nsecond & third")

    def test_joined_message_inherits_author(self):
        self.assertEqual(self.by_id[3]["from"], "Alice")
        self.assertTrue(self.by_id[3]["joined"])

    def test_same_file_reply(self):
        self.assertEqual(self.by_id[4]["reply_to"], 2)

    def test_cross_file_reply_without_onclick(self):
        # regression: href-only form was silently dropped (227 msgs on the real export)
        self.assertEqual(self.by_id[5]["reply_to"], 999)

    def test_reply_to_another_chat_has_no_id_but_is_flagged(self):
        self.assertIsNone(self.by_id[6]["reply_to"])
        self.assertTrue(self.by_id[6]["reply_to_external"])

    def test_links_extracted(self):
        self.assertEqual(self.by_id[4]["links"], ["https://stripe.com/atlas"])

    def test_forward_does_not_steal_the_author(self):
        m = self.by_id[7]
        self.assertEqual(m["from"], "Dave")            # outer author
        self.assertEqual(m["forwarded_from"], "SomeChannel")  # inner source
        self.assertTrue(m["forwarded"])

    def test_forward_text_and_media_captured(self):
        m = self.by_id[7]
        self.assertEqual(m["text"], "forwarded text body")
        self.assertEqual(m["media"]["kind"], "video")
        self.assertEqual(m["media"]["status"], "01:00, 21.4 MB")

    def test_forward_source_reply_kept_separate(self):
        # must NOT land in reply_to: that id belongs to the source chat
        self.assertIsNone(self.by_id[7]["reply_to"])
        self.assertEqual(self.by_id[7]["forwarded_reply_to"], 555)

    def test_multipart_forward_keeps_provenance(self):
        m = self.by_id[8]
        self.assertTrue(m["forwarded"])
        self.assertEqual(m["forwarded_from"], "SomeChannel")  # carried from part 1
        self.assertEqual(m["from"], "Dave")
        self.assertEqual(m["media"]["kind"], "photo")

    def test_forward_carry_resets_on_normal_message(self):
        self.assertNotIn("forwarded_from", self.by_id[9])

    def test_no_message_loses_id_or_author(self):
        chat = [m for m in self.msgs if not m.get("service")]
        self.assertTrue(all(m["id"] is not None for m in chat))
        self.assertTrue(all(m["from"] for m in chat))


class CliTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        with open(os.path.join(cls.tmp, "messages.html"), "w", encoding="utf-8") as fh:
            fh.write(FIXTURE)
        cls.corpus = os.path.join(cls.tmp, "c.jsonl")
        cls._run("parse", cls.tmp, "-o", cls.corpus)

    @staticmethod
    def _run(*a):
        r = subprocess.run([sys.executable, TOOL, *a], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        return r.stdout

    def test_parse_writes_valid_jsonl(self):
        rows = [json.loads(l) for l in open(self.corpus, encoding="utf-8")]
        self.assertEqual(len([r for r in rows if not r.get("service")]), 8)

    def test_search_finds_and_counts(self):
        self.assertEqual(self._run("search", self.corpus, "-e", "stripe", "--count").strip(), "1")

    def test_search_context_pulls_neighbours(self):
        out = self._run("search", self.corpus, "-e", "atlas", "-C", "2")
        self.assertIn("joined message", out)   # neighbour above
        self.assertIn("cross-file reply", out)  # neighbour below

    def test_search_json_format(self):
        rows = json.loads(self._run("search", self.corpus, "-e", "atlas", "--format", "json"))
        self.assertEqual(rows[0]["id"], 4)

    def test_thread_climbs_to_root(self):
        out = self._run("thread", self.corpus, "--id", "4")
        self.assertIn("first", out)          # root (msg 2)
        self.assertIn("»", out)             # the requested msg is marked

    def test_window_range(self):
        out = self._run("window", self.corpus, "--start", "3", "--end", "4")
        self.assertIn("joined message", out)
        self.assertNotIn("next day", out)

    def test_stats_runs(self):
        self.assertIn("date range", self._run("stats", self.corpus))


if __name__ == "__main__":
    unittest.main(verbosity=2)
