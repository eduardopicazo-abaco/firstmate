#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
FIXTURE="$ROOT/.test-spawn"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
cleanup() { env -u TMUX TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null || true; chmod -R u+w "$LAB" 2>/dev/null || true; rm -rf "$LAB" "$FIXTURE"; }
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB"
mkdir -p "$LAB/tmux" "$FIXTURE"
export FM_HOME="$LAB" TMUX_TMPDIR="$LAB/tmux" TREEHOUSE_ROOT="$FIXTURE/pool"
unset TMUX TMUX_PANE FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
# All git objects and Treehouse state belong to this disposable fixture.
git init -q --bare "$FIXTURE/origin.git"
git -C "$FIXTURE/origin.git" symbolic-ref HEAD refs/heads/master
git clone -q "$FIXTURE/origin.git" "$FIXTURE/project"
printf 'Runtime validation fixture.\n' > "$FIXTURE/project/README.md"
git -C "$FIXTURE/project" add README.md
git -C "$FIXTURE/project" -c user.name=Test -c user.email=test@example.invalid commit -qm 'fixture'
git -C "$FIXTURE/origin.git" fetch -q "$FIXTURE/project" HEAD:refs/heads/master
printf 'project 1\n' > "$LAB/config/project-capacity"
printf 'manual\n' > "$LAB/config/backlog-backend"
printf 'codex\n' > "$LAB/config/crew-harness"
tmux -L fm-lab -f /dev/null new-session -d -s primary -x 120 -y 40 -n fm-ordinary -c "$ROOT" "while :; do date +%s >> '$LAB/progress'; sleep 1; done"
export TMUX=$(tmux -L fm-lab display-message -p '#{socket_path},#{pid},0')
printf 'window=primary:fm-ordinary\nbackend=tmux\nkind=ship\nharness=codex\nproject=%s\nworktree=%s\n' "$FIXTURE/project" "$FIXTURE/project" > "$LAB/state/ordinary.meta"
mkdir -p "$LAB/data/p0-proof"
cat > "$LAB/data/p0-proof/brief.md" <<EOF
# Task
## Captain's intent
Reply with PRIORITY_WORKER_READY and remain idle. Do not change files or launch work.
## Firstmate spec
This is a disposable test fixture. Do not initialize any validation pipeline, publish anything, run session startup, or inspect other homes. Do not modify global settings or trust stores. Only respond with the readiness token.
# Definition of done
Delivery contract: mode=no-mistakes
EOF
printf '\n=== Full-capacity ordinary spawn should defer ===\n'
set +e
timeout 100 bin/fm-spawn.sh ordinary-proof "$FIXTURE/project" --mode no-mistakes --yolo off > "$LAB/ordinary.out" 2>&1
ordinary_rc=$?
set -e
cat "$LAB/ordinary.out"
[ "$ordinary_rc" = 75 ]
printf '\n=== P0 should receive its own real Codex worker while ordinary lane continues ===\n'
set +e
timeout 140 bin/fm-spawn.sh p0-proof "$FIXTURE/project" --mode no-mistakes --yolo off --priority 0 > "$LAB/p0.out" 2>&1
spawn_rc=$?
set -e
cat "$LAB/p0.out"
printf 'spawn_exit=%s\n' "$spawn_rc"
tmux -L fm-lab list-windows -t primary -F '#{window_name} #{pane_dead} #{pane_current_command}'
if [ -f "$LAB/state/p0-proof.meta" ]; then cat "$LAB/state/p0-proof.meta"; fi
target=$(sed -n "s/^window=//p" "$LAB/state/p0-proof.meta")
if tmux -L fm-lab has-session -t "$target" 2>/dev/null; then
  sleep 5
  tmux -L fm-lab capture-pane -p -t "$target"
fi
printf '\n=== Ordinary progress continued ===\n'
wc -l "$LAB/progress"
[ "$spawn_rc" = 0 ]
