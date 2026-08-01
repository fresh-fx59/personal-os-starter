#!/usr/bin/env bash
# limit-anchor / install.sh — put anchor-ping.sh on a timer.
#
#   ./install.sh --first-anchor 07:00        # systemd user timer or launchd agent
#   ./install.sh --first-anchor 07:00 --cron # print crontab lines instead
#   ./install.sh --first-anchor 07:00 --dry-run
#   ./install.sh --uninstall
#
# --first-anchor is LOCAL time and should be roughly when your working day
# starts. From it we lay four anchors 5h03m apart; see README.md for why four,
# and why three minutes.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PING="$SELF_DIR/anchor-ping.sh"
UNIT_NAME="limit-anchor-ping"
PLIST_LABEL="com.personal-os.limit-anchor-ping"

FIRST=""; MODE=""; DRY=0; UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --first-anchor) FIRST="${2:-}"; shift 2 ;;
    --cron)         MODE=cron; shift ;;
    --dry-run)      DRY=1; shift ;;
    --uninstall)    UNINSTALL=1; shift ;;
    -h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ---- grid ------------------------------------------------------------------
# Four anchors, 303 minutes apart. Each opens a 5h window; the 3-minute stagger
# keeps every ping safely AFTER the previous window expires even when the timer
# fires a little early. The leftover ~3h51m seam lands opposite your workday.
ANCHOR_COUNT=4
ANCHOR_STEP_MIN=303

compute_grid() { # $1 = HH:MM -> echoes HH:MM per line
  local hhmm="$1" h m t i
  [[ "$hhmm" =~ ^([0-9]{1,2}):([0-9]{2})$ ]] || { echo "bad time: $hhmm (want HH:MM)" >&2; return 1; }
  h=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]}))
  { [ "$h" -le 23 ] && [ "$m" -le 59 ]; } || { echo "bad time: $hhmm" >&2; return 1; }
  t=$(( h * 60 + m ))
  for (( i = 0; i < ANCHOR_COUNT; i++ )); do
    printf '%02d:%02d\n' $(( (t / 60) % 24 )) $(( t % 60 ))
    t=$(( (t + ANCHOR_STEP_MIN) % 1440 ))
  done
}

# ---- uninstall -------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
  if command -v systemctl >/dev/null 2>&1 && [ "$(uname -s)" = Linux ]; then
    systemctl --user disable --now "$UNIT_NAME.timer" 2>/dev/null || :
    rm -f "$HOME/.config/systemd/user/$UNIT_NAME.timer" "$HOME/.config/systemd/user/$UNIT_NAME.service"
    systemctl --user daemon-reload 2>/dev/null || :
    echo "removed systemd user units"
  fi
  if [ "$(uname -s)" = Darwin ]; then
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || launchctl unload "$HOME/Library/LaunchAgents/$PLIST_LABEL.plist" 2>/dev/null || :
    rm -f "$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
    echo "removed launchd agent"
  fi
  echo "(crontab entries, if you used --cron, must be removed by hand: crontab -e)"
  exit 0
fi

[ -n "$FIRST" ] || { echo "--first-anchor HH:MM is required (local time, ~start of your working day)" >&2; exit 2; }
# Not `mapfile` — stock macOS still ships bash 3.2, which does not have it.
TIMES=()
while IFS= read -r _line; do TIMES+=("$_line"); done < <(compute_grid "$FIRST")
[ "${#TIMES[@]}" -eq "$ANCHOR_COUNT" ] || exit 1

echo "anchor grid (local time): ${TIMES[*]}"
echo "  windows:   ${TIMES[0]}→+5h, ${TIMES[1]}→+5h, ${TIMES[2]}→+5h, ${TIMES[3]}→+5h"
echo "  unanchored seam: ~3h51m before ${TIMES[0]}"

[ -x "$PING" ] || chmod +x "$PING" 2>/dev/null || :

emit_cron() {
  echo
  echo "# --- add these to \`crontab -e\` ---"
  echo "# cron runs with a bare PATH: if \`claude\` is not in /usr/bin or /usr/local/bin,"
  echo "# set CLAUDE_BIN to its absolute path in anchor.conf first."
  for t in "${TIMES[@]}"; do
    # mkdir first — the redirect is opened by cron BEFORE the script gets to
    # create its own directory, and a failed redirect turns into daily mail.
    echo "${t#*:} ${t%%:*} * * * mkdir -p \$HOME/.cache/limit-anchor-ping && $PING >> \$HOME/.cache/limit-anchor-ping/anchor.log 2>&1"
  done
}

if [ "$MODE" = cron ]; then emit_cron; exit 0; fi

case "$(uname -s)" in
  Linux)
    command -v systemctl >/dev/null 2>&1 || { echo "no systemctl — falling back to cron:"; emit_cron; exit 0; }
    UDIR="$HOME/.config/systemd/user"
    svc="[Unit]
Description=Anchor the Claude subscription 5h usage window

[Service]
Type=oneshot
ExecStart=$PING
TimeoutStartSec=20m
"
    tmr="[Unit]
Description=Anchor the Claude subscription 5h usage window on a fixed grid

[Timer]
$(for t in "${TIMES[@]}"; do echo "OnCalendar=*-*-* $t:00"; done)
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
"
    if [ "$DRY" = 1 ]; then printf '\n--- %s.service ---\n%s\n--- %s.timer ---\n%s' "$UNIT_NAME" "$svc" "$UNIT_NAME" "$tmr"; exit 0; fi
    mkdir -p "$UDIR"
    printf '%s' "$svc" > "$UDIR/$UNIT_NAME.service"
    printf '%s' "$tmr" > "$UDIR/$UNIT_NAME.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now "$UNIT_NAME.timer"
    echo
    echo "installed. next runs:"
    systemctl --user list-timers "$UNIT_NAME.timer" --no-pager || :
    echo
    echo "NOTE: user timers stop when you log out unless lingering is on:"
    echo "  sudo loginctl enable-linger $USER"
    ;;
  Darwin)
    PLIST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
    intervals=""
    for t in "${TIMES[@]}"; do
      intervals+="        <dict><key>Hour</key><integer>$((10#${t%%:*}))</integer><key>Minute</key><integer>$((10#${t#*:}))</integer></dict>
"
    done
    body="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key><string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$PING</string></array>
    <key>StartCalendarInterval</key>
    <array>
$intervals    </array>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/$PLIST_LABEL.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/$PLIST_LABEL.log</string>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
</dict>
</plist>
"
    if [ "$DRY" = 1 ]; then printf '\n--- %s ---\n%s' "$PLIST" "$body"; exit 0; fi
    mkdir -p "$HOME/Library/LaunchAgents"
    printf '%s' "$body" > "$PLIST"
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || :
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST"
    echo "installed launchd agent: $PLIST"
    echo "log: $HOME/Library/Logs/$PLIST_LABEL.log"
    echo "NOTE: launchd skips runs while the Mac is asleep — it does not catch up."
    ;;
  *)
    echo "unsupported platform $(uname -s) — use cron:"; emit_cron ;;
esac
