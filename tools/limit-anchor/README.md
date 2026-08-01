# limit-anchor

Keep your Claude Code session **warm on your schedule** — fire one tiny ping every
five hours so the rolling usage window opens at times you picked, instead of
whenever your first message of the day happens to land.

```sh
cp anchor.conf.example anchor.conf     # optional, but read it
./install.sh --first-anchor 07:00      # ~when your working day starts, local time
```

That's it. Four timer entries, one throwaway `haiku` call each, and your limit
resets stop landing in the middle of your afternoon.

## The problem it solves

The Claude subscription's five-hour window is **not** a quota that refills on a
clock you control. It **starts on your first request** and expires five hours
later. So the window is anchored by accident:

> You ask one throwaway question at 06:40 while making coffee. That opens a
> window that expires at 11:40. You start real work at 09:00, and at 11:40 —
> right in the middle of it — you're out, with a fresh window you didn't ask for
> and won't finish using.

Anchor it deliberately and the reset is always near a natural break. The ping
costs a handful of tokens: one word, cheapest model, no tools, no project
context.

## The grid: why four anchors, why three minutes

`install.sh --first-anchor 07:00` lays down **four** anchors, **5h03m** apart:

```
07:00 ──5h──▶ 12:00
      12:03 ──5h──▶ 17:03
            17:06 ──5h──▶ 22:06
                  22:09 ──5h──▶ 03:09
                        ░░ 3h51m unanchored seam ░░ 07:00
```

**Four, not five.** Five anchors do not fit in a day, and the failure is
counter-intuitive:

- A fifth ping placed **inside** an open window (say 01:00, inside the
  22:09→03:09 window) doesn't start anything — the window is already running. It
  self-absorbs and anchors nothing.
- A fifth ping placed **in the seam** (say 05:00) anchors 05:00→10:00, which then
  **swallows the 07:00 ping** — and now your unanchored gap has moved from the
  middle of the night into 10:00–12:03, peak working hours. Strictly worse.

So: four anchors, and put the seam where you're asleep. If you change the grid,
simulate the whole chain of windows first — each anchor only lands if the
previous window has already expired.

**Three minutes of stagger.** Anchor *n+1* fires 5h03m after anchor *n*, not 5h
sharp. Timers fire with a little slop (systemd's `AccuracySec`, cron's
second-granularity, a busy machine), and a ping that arrives even a second
*before* the previous window expires is absorbed — it anchors nothing and you
silently lose that slot for the rest of the day. Three minutes is cheap
insurance; the drift it costs you is 9 minutes across a whole day.

**Pick `--first-anchor` to be roughly when you sit down.** Everything else falls
out of it. The times are local and DST-aware (systemd and launchd both follow the
system timezone).

## Install

Requires `bash`, `jq`, and the `claude` CLI (≥ 2.1.186). Linux and macOS.

| Platform | What `install.sh` does |
|----------|------------------------|
| Linux + systemd | writes `~/.config/systemd/user/limit-anchor-ping.{service,timer}`, reloads, enables |
| macOS | writes `~/Library/LaunchAgents/com.personal-os.limit-anchor-ping.plist`, bootstraps it |
| anything else | prints `crontab -e` lines for you to paste |

```sh
./install.sh --first-anchor 07:00              # install
./install.sh --first-anchor 07:00 --dry-run    # show the units, change nothing
./install.sh --first-anchor 07:00 --cron       # print cron lines instead
./install.sh --uninstall                       # remove
```

Two platform gotchas the installer will remind you about:

- **systemd user timers die when you log out.** If this is a server you ssh into,
  `sudo loginctl enable-linger $USER` or the timer only runs while you're
  connected.
- **launchd does not catch up.** A ping scheduled while the Mac is asleep is
  skipped, not deferred — so a laptop that sleeps overnight will miss its early
  anchors. `Persistent=true` gives systemd the catch-up behaviour launchd lacks.

If `claude` isn't on the minimal PATH a timer gets — very common with version
managers — set `CLAUDE_BIN` in `anchor.conf`.

## Verify it's working

```sh
./anchor-ping.sh                                  # run one by hand
systemctl --user list-timers limit-anchor-ping.timer
journalctl --user -u limit-anchor-ping -n 20      # macOS: ~/Library/Logs/com.personal-os.limit-anchor-ping.log
```

A healthy run prints one line:

```
anchor-ping: rc=0 rate_limit_info={"status":"allowed","resetsAt":1785610200,"rateLimitType":"five_hour",...}
```

`resetsAt` is the end of the window you just anchored — check it's five hours
out. The script always exits 0: a timer that goes red because the API was busy is
noise, and the next anchor is only five hours away.

```sh
./anchor-ping.test.sh    # 27 tests, no API calls, no tokens spent
```

## Optional: stamping a pause-at-threshold guard

Off by default, because this starter ships no such guard. If you run a
`PreToolUse` hook that pauses the agent when a window is nearly spent, set
`CC_ANCHOR_STAMP_GUARD_STATE=1` and the ping will record what it learned into the
guard's state file — which is how a *headless* session finds out it's nearly out
of budget, since it has no statusline to notice for it.

Two hard-won rules are baked into that path, and they generalise to any code that
reads this API:

- **Decide on the number, never the status string.** The API reports
  `status: "allowed_warning"` — request still succeeded, exit 0 — when a window
  merely *approaches* its cap. Treating `status != "allowed"` as "limited" once
  stamped 100% at 56% real usage, and the guard then denied every tool call for
  ninety minutes. Read `utilization`, compare it against your own threshold.
- **Merge, don't clobber.** This ping learns about one window; something else may
  have recorded the other. Writing only yours can erase a longer, more severe
  window and silently downgrade a correct pause. Merge into a fresh snapshot,
  start from empty only when the file is missing, stale, or malformed.

Range-check anything you read, too: `utilization` is a 0–1 fraction today, and
the code refuses values outside 0–1.5 so that a future switch to 0–100 fails
*open* rather than reading 99 as 9900%.

## What this is not

- **Not a way to get more usage.** The ping costs a few tokens and moves your
  window; it doesn't enlarge it.
- **Not session continuity.** Warm *window* ≠ warm *context*. To resume a
  conversation, use `claude --continue` (last session in this directory) or
  `claude --resume` (picker). Sessions are kept 30 days.
- **Not a rate-limit guard.** It reports what it sees; it doesn't pause anything
  on its own.
