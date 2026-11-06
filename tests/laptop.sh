#!/usr/bin/env bash
# Exercise hardware gating, read-only drift checks and wrappers without host writes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export HOME="$scratch/home" CONFIG_POWER_SUPPLY_ROOT="$scratch/power" CONFIG_BATTERY_RULE="$scratch/etc/charge.rules"
export MOCK_CALLS="$scratch/calls"
export XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share" XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME/.local/share/voxtype/models" "$HOME/.config/omarchy/defaults" "$scratch/bin" "$CONFIG_POWER_SUPPLY_ROOT"
: >"$MOCK_CALLS"
cat >"$scratch/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$MOCK_CALLS"
case "$1" in install) exec "$@" ;; udevadm) exit 0 ;; *) exit 99 ;; esac
SH
cat >"$scratch/bin/omarchy" <<'SH'
#!/bin/bash
printf 'omarchy %s\n' "$*" >>"$MOCK_CALLS"
if [[ "$1 $2" == 'powerprofiles set' && $3 != autodetect ]]; then
  mkdir -p "$HOME/.local/state/omarchy/powerprofiles"
  printf '%s\n' "$4" >"$HOME/.local/state/omarchy/powerprofiles/$3"
fi
if [[ "$1 $2" == 'dictation use' ]]; then
  printf '%s\n' "$3" >"$HOME/.config/omarchy/defaults/dictation"
fi
SH
for cmd in systemctl powerprofilesctl voxtype; do
    printf '#!/bin/sh\nexit 0\n' >"$scratch/bin/$cmd"
done
chmod +x "$scratch/bin/"*
export PATH="$scratch/bin:/usr/bin:/bin"
printf 'voxtype\n' >"$HOME/.config/omarchy/defaults/dictation"
printf 'model\n' >"$HOME/.local/share/voxtype/models/ggml-medium.bin"

run_laptop() {
    bash -c 'set -euo pipefail; SCRIPT_DIR=$1 CHECK=$2 DRIFT=0 OS_NAME=Linux; source "$1/scripts/lib/report.sh"; source "$1/scripts/lib/copy.sh"; source "$1/scripts/apply/laptop.sh"; echo "drift=$DRIFT"' laptop "$ROOT" "$1"
}

# Unsupported hardware never needs root. Read-only checks never create preferences.
run_laptop 1 >"$scratch/check"
! test -e "$HOME/.local/state"
! test -s "$MOCK_CALLS"
run_laptop 0 >"$scratch/apply"
! grep -q '^sudo ' "$MOCK_CALLS"
grep -q 'powerprofiles set autodetect' "$MOCK_CALLS"
run_laptop 1 | grep -qx 'drift=0'

mkdir -p "$CONFIG_POWER_SUPPLY_ROOT/BAT0"
printf '85\n' >"$CONFIG_POWER_SUPPLY_ROOT/BAT0/charge_control_start_threshold"
printf '90\n' >"$CONFIG_POWER_SUPPLY_ROOT/BAT0/charge_control_end_threshold"
: >"$MOCK_CALLS"
run_laptop 1 >"$scratch/check"
grep -q 'charge.rules: missing' "$scratch/check"
! test -e "$CONFIG_BATTERY_RULE"
! test -s "$MOCK_CALLS"
run_laptop 0 >"$scratch/apply"
cmp "$ROOT/system/udev/99-battery-charge-threshold.rules" "$CONFIG_BATTERY_RULE"
run_laptop 1 | grep -qx 'drift=0'
printf '80\n' >"$CONFIG_POWER_SUPPLY_ROOT/BAT0/charge_control_end_threshold"
run_laptop 1 >"$scratch/check"
grep -q 'expected 90 percent' "$scratch/check"
test "$(cat "$CONFIG_POWER_SUPPLY_ROOT/BAT0/charge_control_end_threshold")" = 80

# Seed audits reveal drift without printing secrets or overwriting local state.
printf '{"secret":"local-test-secret"}\n' >"$scratch/local.json"
printf '{"theme":"system"}\n' >"$scratch/seed.json"
bash -c 'CHECK=1 CHECK_SEEDS=1 DRIFT=0; source "$1/scripts/lib/copy.sh"; copy_required_if_missing "$2/seed.json" "$2/local.json"' seed "$ROOT" "$scratch" >"$scratch/seed-check"
grep -q 'seed differs' "$scratch/seed-check"
! grep -q local-test-secret "$scratch/seed-check"
grep -q local-test-secret "$scratch/local.json"

cat >"$scratch/bin/opencode" <<'SH'
#!/bin/sh
printf 'opencode %s\n' "$*" >>"$MOCK_CALLS"
SH
cat >"$scratch/bin/op" <<'SH'
#!/bin/sh
printf 'op %s\n' "$*" >>"$MOCK_CALLS"
SH
cat >"$scratch/bin/claude" <<'SH'
#!/bin/sh
printf 'claude config=%s args=%s\n' "$CLAUDE_CONFIG_DIR" "$*" >>"$MOCK_CALLS"
SH
chmod +x "$scratch/bin/"*
: >"$MOCK_CALLS"
env -u OPENROUTER_API_KEY -u GEMINI_API_KEY -u GOOGLE_GENERATIVE_AI_API_KEY -u OPENCODE_BIN sh "$ROOT/bin/opencode-op" --version
grep -q '^opencode --version' "$MOCK_CALLS"
! grep -q '^op ' "$MOCK_CALLS"
: >"$MOCK_CALLS"
OPENROUTER_API_KEY=test GEMINI_API_KEY=test OPENCODE_BIN="$scratch/bin/opencode" sh "$ROOT/bin/opencode-op" run 'hello world'
grep -q '^opencode run hello world' "$MOCK_CALLS"
! grep -q '^op ' "$MOCK_CALLS"
env -u OPENROUTER_API_KEY -u GEMINI_API_KEY -u GOOGLE_GENERATIVE_AI_API_KEY -u OPENCODE_BIN sh "$ROOT/bin/opencode-op" run
grep -q '^op run --env-file=' "$MOCK_CALLS"
sh "$ROOT/bin/claude-api" --version
grep -q "claude config=$HOME/.claude-api args=--version" "$MOCK_CALLS"
echo 'Laptop preferences and credential wrapper tests passed'
