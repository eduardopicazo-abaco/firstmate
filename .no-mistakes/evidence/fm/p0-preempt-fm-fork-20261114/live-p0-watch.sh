#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
cleanup() { env -u TMUX TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null || true; rm -rf "$LAB"; }
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB"
mkdir -p "$LAB/tmux"
export FM_HOME="$LAB"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
export TMUX_TMPDIR="$LAB/tmux"
unset TMUX TMUX_PANE
# Real private terminals; the ordinary lane keeps making observable progress.
tmux -L fm-lab -f /dev/null new-session -d -s primary -x 120 -y 40 -n fm-p0-a -c "$ROOT" 'sleep 900'
tmux -L fm-lab new-window -t primary -n fm-p0-b -c "$ROOT" 'sleep 900'
tmux -L fm-lab new-window -t primary -n fm-ordinary -c "$ROOT" "while :; do date +%s >> '$LAB/progress'; sleep 1; done"
for id in p0-a p0-b ordinary; do
  printf 'window=primary:fm-%s\nbackend=tmux\nkind=ship\nharness=codex\n' "$id" > "$LAB/state/$id.meta"
  if [ "$id" != ordinary ]; then printf 'priority=0\n' >> "$LAB/state/$id.meta"; fi
done
now=$(date +%s)
opened=$((now-601))
printf 'blocked [key=deploy] [at=%s]: missing deploy key\nworking [at=%s]: checking alternate route\nblocked [key=deploy] [at=%s]: missing deploy key\nresolved [key=other] [at=%s]: unrelated answer\n' "$opened" "$now" "$now" "$now" > "$LAB/state/p0-a.status"
printf 'blocked [at=%s]: network route unavailable\n' "$opened" > "$LAB/state/p0-b.status"
printf 'blocked [at=%s]: fresh ordinary sibling signal\n' "$now" > "$LAB/state/ordinary.status"
run_cycle() {
  env FM_WATCH_HANDLING_SUCCESSOR=1 FM_WATCH_ONCE=1 FM_POLL=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 timeout 45 bin/fm-watch.sh
}
ack() {
  bin/fm-wake-drain.sh > "$LAB/drain.out" 2> "$LAB/drain.err"
  cat "$LAB/drain.out"
  local sequence generation
  sequence=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation [A-Za-z0-9._-][A-Za-z0-9._-]*$/\1/p' "$LAB/drain.err")
  generation=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through [0-9][0-9]* --recovery-generation \([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1/p' "$LAB/drain.err")
  bin/fm-wake-drain.sh --ack-through "$sequence" --recovery-generation "$generation"
}
printf '\n=== Two overdue P0 blockers, repeated note and unrelated resolution ===\n'
run_cycle | tee "$LAB/first.out"
grep -F 'P0 blocker open' "$LAB/first.out" | grep -F 'missing deploy key'
grep -F 'P0 blocker open' "$LAB/first.out" | grep -F 'network route unavailable'
ack
printf '\n=== Re-arm: same episodes must not alarm twice; ordinary signal remains ===\n'
printf 'working [at=%s]: ongoing investigation\n' "$(date +%s)" >> "$LAB/state/p0-a.status"
run_cycle | tee "$LAB/second.out"
if grep -F 'P0 blocker open' "$LAB/second.out"; then exit 1; fi
ack
printf '\n=== Resolve and reopen: a new episode gets a new alarm ===\n'
printf 'resolved [key=deploy] [at=%s]: key restored\nblocked [key=deploy] [at=%s]: missing deploy key\n' "$now" "$((now-600))" >> "$LAB/state/p0-a.status"
run_cycle | tee "$LAB/third.out"
grep -F 'P0 blocker open' "$LAB/third.out" | grep -F 'missing deploy key'
printf '\n=== Existing ordinary lane still running ===\n'
tmux -L fm-lab list-windows -t primary -F '#{window_name} #{pane_dead}'
cat "$LAB/progress"
[ "$(wc -l < "$LAB/progress")" -ge 2 ]
printf '\nPASS: real watcher alarm, once-only delivery, reopening and parallel lane progress; no backend stubs or fake clock.\n'
