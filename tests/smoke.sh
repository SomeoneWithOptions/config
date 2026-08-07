#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/1 SoftwareInstall.sh" "$ROOT/2 Fonts.sh" "$ROOT/3 Git.sh" \
  "$ROOT/4 ConfigFiles.sh" "$ROOT/5 Keys.sh" "$ROOT/bootstrap.sh" "$ROOT"/bin/*
python -m json.tool "$ROOT/zed/settings.json" >/dev/null
python -m json.tool "$ROOT/pi/agent/settings.json" >/dev/null
node "$ROOT/pi/agent/extensions/worktree.ts" --self-test >/dev/null

# Zen: the top-edge hover fix needs both halves, chrome CSS is inert without the pref.
grep -q 'legacyUserProfileCustomizations.stylesheets", true' "$ROOT/zen/user.js"
grep -q '#zen-appcontent-navbar-wrapper' "$ROOT/zen/userChrome.css"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/power/AC0" "$tmp/runtime"
printf 'Mains\n' >"$tmp/power/AC0/type"
printf '0\n' >"$tmp/power/AC0/online"
cat >"$tmp/bin/powerprofilesctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALLS"
EOF
chmod +x "$tmp/bin/powerprofilesctl"
export CALLS="$tmp/calls"

run_battery_mode() {
  POWER_SUPPLY_ROOT="$tmp/power" XDG_RUNTIME_DIR="$tmp/runtime" \
    PATH="$tmp/bin:$PATH" "$ROOT/bin/battery-power-mode"
}

run_battery_mode
run_battery_mode
[ "$(wc -l <"$CALLS")" -eq 1 ]
grep -qx 'set power-saver' "$CALLS"
printf '1\n' >"$tmp/power/AC0/online"
run_battery_mode
tail -n 1 "$CALLS" | grep -qx 'set balanced'

printf 'smoke tests passed\n'
