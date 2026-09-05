#!/usr/bin/env bash
# Hermetic regression test for Omarchy's system-update entrypoint.
# No installs, sudo, network, package queries, or host updates.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/report/actions" "$WORK/report/stages"
: >"$WORK/calls"
: >"$WORK/report/warnings"

cat >"$WORK/bin/uname" <<'SH'
#!/bin/sh
printf 'Linux\n'
SH
cat >"$WORK/bin/pacman" <<'SH'
#!/bin/sh
printf 'pacman %s\n' "$*" >>"$MOCK_CALLS"
exit 99
SH
cat >"$WORK/bin/omarchy" <<'SH'
#!/bin/sh
printf 'omarchy %s\n' "$*" >>"$MOCK_CALLS"
if [ "$#" -eq 2 ] && [ "$1" = update ] && [ "$2" = -y ] && \
  [ "${OMARCHY_UPDATE_LOGGED:-}" = 1 ]; then
  printf 'mock update failure\n' >&2
  exit 42
fi
printf 'unexpected Omarchy operation after failed update: %s\n' "$*" >&2
exit 99
SH
cat >"$WORK/bin/sudo" <<'SH'
#!/bin/sh
printf 'sudo %s\n' "$*" >>"$MOCK_CALLS"
printf 'unexpected sudo\n' >&2
exit 99
SH
chmod +x "$WORK/bin/"*

status=0
env HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" MOCK_CALLS="$WORK/calls" \
  OMARCHY_UPDATE_LOG_FILE="$WORK/omarchy-update.log" \
  BOOTSTRAP_REPORT_DIR="$WORK/report" BOOTSTRAP_STAGE=software \
  bash "$ROOT/1 SoftwareInstall.sh" >"$WORK/output" 2>&1 || status=$?

[[ $status == 42 ]]
[[ $(grep -c '^omarchy update -y$' "$WORK/calls") == 1 ]]
[[ $(wc -l <"$WORK/calls") == 1 ]]
[[ $(stat -c '%a' "$WORK/omarchy-update.log") == 600 ]]
grep -q 'mock update failure' "$WORK/output" "$WORK/omarchy-update.log"
! grep -q '^pacman ' "$WORK/calls"
! grep -q '^sudo ' "$WORK/calls"
grep -q 'WARNING: Omarchy system update failed; subsequent package operations were stopped.' "$WORK/output"
grep -q 'software: Omarchy system update failed; subsequent package operations were stopped.' "$WORK/report/warnings"
test -f "$WORK/report/stages/software.warning"
test -f "$WORK/report/stages/software.action"
grep -q 'Omarchy update → retry' "$WORK/report/actions/system-update"
grep -q 'Run: omarchy update -y' "$WORK/report/actions/system-update"
! grep -q 'OMARCHY_ALLOW_DIRECT_PACMAN' "$ROOT/1 SoftwareInstall.sh"
! grep -Eq 'pacman[[:space:]]+-S(yu|uy)|pacman[[:space:]]+-Syu' "$ROOT/1 SoftwareInstall.sh"

printf 'software update tests passed\n'
