#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
LAB="$ROOT/.test-tmp/p0-boundary-live"
EVIDENCE=/home/edy/.no-mistakes/evidence/01M7E1CDQ9MFV8G4ZXEZBXQ822
REAL_TMUX=$(command -v tmux)
SOCKET="$ROOT/.p0.sock"
mkdir -p "$LAB/home/"{state,data,config,projects} "$LAB/user" "$LAB/fakebin" "$LAB/tmp"
trap '"$REAL_TMUX" -S "$SOCKET" kill-server 2>/dev/null || true' EXIT
unset TMUX TMUX_PANE HERDR_ENV HERDR_SESSION HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_TAB_ID HERDR_WORKSPACE_ID
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_WATCH_NOW
export FM_HOME="$LAB/home" HOME="$LAB/user" TMPDIR="$LAB/tmp"
cat > "$LAB/fakebin/tmux" <<EOF
#!/usr/bin/env bash
exec '$REAL_TMUX' -S '$SOCKET' "\$@"
EOF
chmod +x "$LAB/fakebin/tmux"
export PATH="$LAB/fakebin:$PATH"
"$REAL_TMUX" -S "$SOCKET" -f /dev/null new-session -d -s proof -n fm-first 'sleep 3600'
"$REAL_TMUX" -S "$SOCKET" new-window -d -t proof -n fm-second 'sleep 3600'
for id in first second; do
  printf 'window=proof:fm-%s\nbackend=tmux\nharness=codex\nkind=ship\npriority=0\ntmux_socket=%s\n' "$id" "$SOCKET" > "$FM_HOME/state/$id.meta"
done
cycle() {
  local label=$1
  printf '\n--- %s real_epoch=%s ---\n' "$label" "$(date +%s)"
  FM_WATCH_HANDLING_SUCCESSOR=1 FM_WATCH_ONCE=1 FM_POLL=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 FM_WORKTREE_CLEANUP=0 \
    bash "$ROOT/bin/fm-watch.sh" > "$LAB/output"
  cat "$LAB/output"
  if [ -f "$FM_HOME/state/.wake-queue" ]; then cat "$FM_HOME/state/.wake-queue"; fi
  bash "$ROOT/bin/fm-wake-drain.sh" > "$LAB/drain" 2> "$LAB/drain.err"
  cat "$LAB/drain" "$LAB/drain.err"
  local sequence generation
  sequence=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation .*/\1/p' "$LAB/drain.err")
  generation=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$LAB/drain.err")
  if [ -n "$sequence" ]; then bash "$ROOT/bin/fm-wake-drain.sh" --ack-through "$sequence" --recovery-generation "$generation"; fi
}
alarm() { grep -F "$1" "$LAB/output" >/dev/null || { echo "FAIL missing alarm: $1"; exit 1; }; }
no_alarm() { if grep -F 'P0 blocker' "$LAB/output"; then echo 'FAIL unexpected alarm'; exit 1; fi; }
now=$(date +%s)
opened=$((now - 580))
printf 'blocked [key=deploy] [at=%s]: original deployment blocker\n' "$opened" > "$FM_HOME/state/first.status"
cycle before-deadline
no_alarm
# Align to the actual deadline, without a fake date command or watcher clock override.
while [ "$(date +%s)" -lt "$((opened+600))" ]; do sleep 0.05; done
cycle at-deadline
alarm 'P0 blocker open for 600s:'
grep -F 'original deployment blocker' "$LAB/drain" >/dev/null
cycle after-deadline-dedup
no_alarm
# Simultaneous keys and workers; later note retains original opening age.
now=$(date +%s)
printf 'blocked [key=route] [at=%s]: route unavailable\nblocked [key=approval] [at=%s]: approval unavailable\nblocked [key=route] [at=%s]: updated route note\n' "$((now-650))" "$((now-640))" "$now" >> "$FM_HOME/state/first.status"
printf 'blocked [key=second] [at=%s]: second worker blocker\n' "$((now-610))" > "$FM_HOME/state/second.status"
cycle multiple-blockers-note-update
alarm 'updated route note'
alarm 'approval unavailable'
alarm 'second worker blocker'
grep -E 'open for 65[0-9]s:.*updated route note' "$LAB/output" >/dev/null
printf 'resolved [key=deploy]: deployment ready\nresolved [key=route]: route ready\nresolved [key=approval]: approved\n' >> "$FM_HOME/state/first.status"
printf 'resolved [key=second]: ready\n' >> "$FM_HOME/state/second.status"
cycle resolved
no_alarm
! grep -F 'blocked:' "$LAB/drain"
now=$(date +%s)
printf 'blocked [key=route] [at=%s]: reopened route\n' "$now" >> "$FM_HOME/state/first.status"
cycle reopened-fresh
no_alarm
# Backdated synthetic new episode, observed through the real owner and queue.
printf 'resolved [key=route]: ready again\nblocked [key=route] [at=%s]: reopened aged route\n' "$((now-601))" >> "$FM_HOME/state/first.status"
cycle reopened-overdue
alarm 'reopened aged route'
printf 'resolved [key=route]: ready\nblocked [key=missing]: timestamp absent\nblocked [key=malformed] [at=invalid]: timestamp invalid\nblocked [key=future] [at=%s]: timestamp future\n' "$((now+3600))" >> "$FM_HOME/state/first.status"
cycle invalid-timestamps
alarm 'opening timestamp missing or malformed: blocked [key=missing]'
alarm 'opening timestamp missing or malformed: blocked [key=malformed]'
alarm 'opening timestamp is in the future:'
printf 'resolved [key=missing]: fixed\nresolved [key=malformed]: fixed\nresolved [key=future]: fixed\n' >> "$FM_HOME/state/first.status"
cycle invalid-resolved
no_alarm
for mode in away quiet; do
  if [ "$mode" = quiet ]; then export FM_AFK_MODE=quiet; else unset FM_AFK_MODE; fi
  bash "$ROOT/bin/fm-afk-contract.sh" enter --words 'Continue already authorized synthetic priority work.' --spend 1
  touch "$FM_HOME/state/.afk"
  bash "$ROOT/bin/fm-afk-contract.sh" mode
  now=$(date +%s)
  printf 'blocked [key=%s] [at=%s]: %s delivery blocker\n' "$mode" "$((now-601))" "$mode" >> "$FM_HOME/state/first.status"
  cycle "$mode-alarm-delivery"
  alarm "$mode delivery blocker"
  grep -F "$mode delivery blocker" "$LAB/drain" >/dev/null
  cycle "$mode-no-duplicate"
  no_alarm
  printf 'resolved [key=%s]: answered\n' "$mode" >> "$FM_HOME/state/first.status"
  cycle "$mode-resolved"
  no_alarm
  rm "$FM_HOME/state/.afk"
  bash "$ROOT/bin/fm-afk-contract.sh" archive
 done
bash "$ROOT/bin/fm-branch-prompt.sh" > "$EVIDENCE/emitted-supervision-prompt-boundary-live.txt"
printf '\nPASS: native real-clock boundaries, simultaneous blockers, note ages, resolution/reopening, invalid timestamps, away/quiet queue and drain delivery; full prompt captured.\n'
