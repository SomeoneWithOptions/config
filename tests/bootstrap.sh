#!/usr/bin/env bash
# Hermetic logging tests: no installs, sudo, network, desktop changes, or secrets.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
RUN_DIRS=()
cleanup() {
  rm -rf "$WORK"
  if ((${#RUN_DIRS[@]})); then rm -rf "${RUN_DIRS[@]}"; fi
}
trap cleanup EXIT
mkdir -p "$WORK/bin" "$WORK/repo with spaces/lib" "$WORK/home"
REPO="$WORK/repo with spaces"
cp "$ROOT/lib/report.sh" "$REPO/lib/report.sh"

cat >"$WORK/bin/systemd-inhibit" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  case "$1" in --*) shift ;; *) exec "$@" ;; esac
done
exit 99
SH
cat >"$WORK/bin/sudo" <<'SH'
#!/bin/sh
echo 'unexpected sudo' >&2
exit 99
SH
cat >"$WORK/bin/curl" <<'SH'
#!/bin/sh
if [ -n "${MOCK_ARCHIVE:-}" ]; then
  while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then cp "$MOCK_ARCHIVE" "$2"; exit; fi
    shift
  done
fi
echo 'mock download failed' >&2
exit 28
SH
cat >"$WORK/bin/sleep" <<'SH'
#!/bin/sh
if [ "${MOCK_FAST_HEARTBEAT:-0}" = 1 ] && [ "$1" = 1 ]; then
  exec /bin/sleep 0.01
fi
exec /bin/sleep "$@"
SH
cat >"$WORK/bin/gdbus" <<'SH'
#!/bin/sh
case "$*" in *org.freedesktop.Secret.Service.SearchItems*) ;; *) exit 99 ;; esac
case "${MOCK_KEYRING:-missing}" in
  present) echo "([objectpath '/org/freedesktop/secrets/collection/login/1'], @ao [])" ;;
  missing) echo '(@ao [], @ao [])' ;;
  locked) echo "(@ao [], [objectpath '/org/freedesktop/secrets/collection/login/1'])" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$WORK/bin/"*

cat >"$REPO/1 SoftwareInstall.sh" <<'SH'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/report.sh"
echo 'RAW SOFTWARE OUTPUT'
echo 'RAW SOFTWARE STDERR' >&2
report_warning 'mock optional package failed'
if [[ ${BOOTSTRAP_KEYS:-1} == 1 ]]; then
  report_action ssh-keys 'Old key reminder' 'should be replaced'
fi
SH
for script in '2 Fonts.sh' '3 Git.sh' '4 ConfigFiles.sh'; do
  printf '#!/bin/bash\nprintf "RAW %%s OUTPUT\\n" "$0"\n' >"$REPO/$script"
done
cat >"$REPO/5 Keys.sh" <<'SH'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/report.sh"
report_keys_action
report_deferred
SH

run_bootstrap() {
  local expected=$1
  shift
  local status=0
  env HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" \
    BOOTSTRAP_ALLOW_CONFIG_DIR=1 CONFIG_DIR="$REPO" \
    BOOTSTRAP_SUDO=0 BOOTSTRAP_KEYS=1 BOOTSTRAP_VERBOSE=0 NO_COLOR=1 TMPDIR="$WORK" \
    "$@" sh "$ROOT/bootstrap.sh" >"$WORK/output" 2>&1 || status=$?
  LOG=$(awk '/^Detailed log: / { print $3; exit }' "$WORK/output")
  [[ -f $LOG ]]
  RUN_DIRS+=("${LOG%/*}")
  if [[ $status != "$expected" ]]; then
    printf 'Expected exit %s, got %s\n' "$expected" "$status" >&2
    cat "$WORK/output" >&2
    exit 1
  fi
}

run_bootstrap 0
! grep -q 'RAW ' "$WORK/output"
grep -q 'RAW SOFTWARE OUTPUT' "$LOG"
grep -q 'RAW SOFTWARE STDERR' "$LOG"
grep -q 'Software — completed with warnings' "$WORK/output"
grep -q 'SSH keys — deferred; action needed' "$WORK/output"
grep -q 'Setup finished with warnings' "$WORK/output"
grep -q 'mock optional package failed' "$WORK/output"
grep -q 'ACTION NEEDED · 1' "$WORK/output"
! grep -q 'Old key reminder' "$WORK/output"
! grep -q $'\033' "$WORK/output"
python3 - "$LOG" "$WORK/output" <<'PY'
import pathlib, stat, sys
log = pathlib.Path(sys.argv[1])
assert stat.S_IMODE(log.stat().st_mode) == 0o600
assert stat.S_IMODE(log.parent.stat().st_mode) == 0o700
assert stat.S_IMODE((log.parent / 'summary.txt').stat().st_mode) == 0o600
out = pathlib.Path(sys.argv[2]).read_text()
assert out.index('ACTION NEEDED') > out.index('SSH keys — deferred')
assert 'repo\\ with\\ spaces/5\\ Keys.sh' in out
PY

# Archive path exercises the same curl | sh bootstrap entry without a network.
tar -czf "$WORK/repo.tar.gz" -C "$WORK" 'repo with spaces'
run_bootstrap 0 BOOTSTRAP_ALLOW_CONFIG_DIR=0 MOCK_ARCHIVE="$WORK/repo.tar.gz"
[[ -f ${LOG%/*}/source/repo\ with\ spaces/lib/report.sh ]]
grep -q 'SSH keys — deferred' "$WORK/output"

run_bootstrap 0 BOOTSTRAP_VERBOSE=1
grep -q 'RAW SOFTWARE OUTPUT' "$WORK/output"
grep -q 'RAW SOFTWARE STDERR' "$WORK/output"

run_bootstrap 0 BOOTSTRAP_KEYS=0
grep -q 'SSH keys skipped (BOOTSTRAP_KEYS=0)' "$WORK/output"
! grep -q 'ACTION NEEDED' "$WORK/output"

run_bootstrap 99 BOOTSTRAP_SUDO=1
grep -q 'Setup stopped — sudo authentication (exit 99)' "$WORK/output"
! grep -q 'START Software' "$LOG"

cp "$REPO/2 Fonts.sh" "$WORK/fonts.original"
printf '#!/bin/bash\n/bin/sleep 0.6\n' >"$REPO/2 Fonts.sh"
run_bootstrap 0 MOCK_FAST_HEARTBEAT=1
grep -q 'Fonts still running' "$WORK/output"
printf '#!/bin/bash\necho "mock font failure" >&2\nexit 23\n' >"$REPO/2 Fonts.sh"
run_bootstrap 23
grep -q 'Fonts — failed (exit 23)' "$WORK/output"
grep -q 'Setup stopped — Fonts (exit 23)' "$WORK/output"
grep -q 'mock font failure' "$LOG"
! grep -q 'START Git' "$LOG"
grep -q 'ACTION NEEDED' "$WORK/output"
cp "$WORK/fonts.original" "$REPO/2 Fonts.sh"

cp "$REPO/5 Keys.sh" "$WORK/keys.original"
printf '#!/bin/bash\nexit 17\n' >"$REPO/5 Keys.sh"
run_bootstrap 17
grep -q 'SSH keys — failed (exit 17)' "$WORK/output"
cp "$WORK/keys.original" "$REPO/5 Keys.sh"

run_bootstrap 28 BOOTSTRAP_ALLOW_CONFIG_DIR=0 CONFIG_ARCHIVE_URL=https://example.invalid/archive
grep -q 'mock download failed' "$LOG"
grep -q 'Setup stopped — preparation (exit 28)' "$WORK/output"
run_bootstrap 1 CONFIG_DIR="$WORK/not-a-repo"
grep -q 'CONFIG_DIR is not this config repo' "$LOG"

printf '#!/bin/bash\nkill -TERM "$PPID"\nsleep 0.2\n' >"$REPO/2 Fonts.sh"
run_bootstrap 143
grep -q 'Setup stopped — Fonts (exit 143)' "$WORK/output"
cp "$WORK/fonts.original" "$REPO/2 Fonts.sh"

# Linear probes inspect metadata only; unknown keyring state is not "missing".
setup="$WORK/home/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup"
mkdir -p "${setup%/*}" "$WORK/home/.config/omarchy/linear"
printf '#!/bin/sh\necho "setup must not run in a readiness probe" >&2\nexit 99\n' >"$setup"
chmod +x "$setup"
probe_linear() {
  env HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" MOCK_KEYRING="$1" \
    bash -c '. "$1/lib/report.sh"; report_linear_action' bash "$ROOT" >"$WORK/linear-output"
}
probe_linear missing
grep -q 'Linear → API key + team/project' "$WORK/linear-output"
grep -q 'config.lua' "$WORK/linear-output"
printf 'return {\n  team = "Engineering",\n  project = "Work",\n}\n' >"$WORK/home/.config/omarchy/linear/config.lua"
probe_linear present
[[ ! -s "$WORK/linear-output" ]]
probe_linear locked
grep -q 'not confirmed (locked)' "$WORK/linear-output"
probe_linear unavailable
grep -q 'not confirmed (unknown)' "$WORK/linear-output"
probe_linear missing
grep -q 'not confirmed (missing)' "$WORK/linear-output"

# Real key script: signed-out is deferred; op read failures stay failures.
cat >"$WORK/bin/op" <<'SH'
#!/bin/sh
case "$1" in
  whoami) exit "${MOCK_OP_STATUS:-1}" ;;
  read)
    if [ "${MOCK_OP_READ_FAIL:-1}" = 1 ]; then
      echo 'mock op read failure' >&2; exit 19
    fi
    case "$2" in
      */fingerprint) echo MOCK-FINGERPRINT ;;
      */'key type') echo RSA ;;
      *) echo MOCK-PRIVATE-KEY-MUST-NOT-BE-LOGGED ;;
    esac
    exit 0
    ;;
esac
exit 99
SH
cat >"$WORK/bin/uname" <<'SH'
#!/bin/sh
echo Darwin
SH
cat >"$WORK/bin/launchctl" <<'SH'
#!/bin/sh
echo com.openssh.ssh-agent
SH
chmod +x "$WORK/bin/op" "$WORK/bin/uname" "$WORK/bin/launchctl"
env HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" TMPDIR="$WORK" \
  bash "$ROOT/5 Keys.sh" >"$WORK/keys-output" 2>&1
grep -q '1Password → SSH keys' "$WORK/keys-output"
status=0
env HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" MOCK_OP_STATUS=0 TMPDIR="$WORK" \
  bash "$ROOT/5 Keys.sh" >"$WORK/keys-output" 2>&1 || status=$?
[[ $status == 19 ]]
grep -q 'mock op read failure' "$WORK/keys-output"

# Exercise the real SSH passphrase follow-up without starting a real agent.
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/ssh-add"
printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/ssh-keygen"
chmod +x "$WORK/bin/ssh-add" "$WORK/bin/ssh-keygen"
cp "$ROOT/5 Keys.sh" "$REPO/5 Keys.sh"
run_bootstrap 0 MOCK_OP_STATUS=0 MOCK_OP_READ_FAIL=0 SSH_AUTH_SOCK=/mock/agent.sock
grep -q 'SSH key → enter passphrase' "$WORK/output"
grep -q 'ssh-add --apple-use-keychain' "$WORK/output"
! grep -q '1Password → SSH keys' "$WORK/output"
! grep -q 'MOCK-PRIVATE-KEY-MUST-NOT-BE-LOGGED' "$LOG" "$WORK/output"

# Completely configured run: no warning or action headings.
printf '#!/bin/bash\necho "software ready"\n' >"$REPO/1 SoftwareInstall.sh"
printf '#!/bin/bash\nexit 0\n' >"$REPO/5 Keys.sh"
run_bootstrap 0
grep -q '✓ SSH keys' "$WORK/output"
grep -q '^Setup finished\.$' "$WORK/output"
! grep -Eq 'WARNINGS|ACTION NEEDED' "$WORK/output"

# --check must keep its diff contract without creating reporting records.
mkdir -p "$WORK/check-report/actions" "$WORK/check-report/stages" "$WORK/check-home"
env HOME="$WORK/check-home" PATH="$WORK/bin:/usr/bin:/bin" \
  BOOTSTRAP_REPORT_DIR="$WORK/check-report" \
  bash "$ROOT/4 ConfigFiles.sh" --check >"$WORK/check-output" 2>&1
[[ -z $(find "$WORK/check-home" -mindepth 1 -print -quit) ]]
[[ -z $(find "$WORK/check-report" -type f -print -quit) ]]
grep -q '^== ' "$WORK/check-output"
grep -q 'managed target(s) differ from the repo' "$WORK/check-output"

# Omarchy idle inhibition starts before package work and restores prior state.
cat >"$WORK/bin/omarchy" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/idle-calls"
marker="$HOME/.local/state/omarchy/indicators/stay-awake"
case "$*" in
  'toggle idle stay-awake')
    [ "${MOCK_IDLE_FAIL:-0}" = 0 ] || exit 42
    mkdir -p "${marker%/*}"; touch "$marker" ;;
  'toggle idle allow-idle') rm -f "$marker" ;;
  *) exit 99 ;;
esac
SH
chmod +x "$WORK/bin/omarchy"
printf '#!/bin/sh\necho Linux\n' >"$WORK/bin/uname"
printf '#!/bin/bash\ntest -f "$HOME/.local/state/omarchy/indicators/stay-awake"\n' >"$REPO/1 SoftwareInstall.sh"
marker="$WORK/home/.local/state/omarchy/indicators/stay-awake"
run_bootstrap 0
[[ ! -f $marker ]]
grep -qx 'toggle idle stay-awake' "$WORK/home/idle-calls"
grep -qx 'toggle idle allow-idle' "$WORK/home/idle-calls"
touch "$marker"
: >"$WORK/home/idle-calls"
run_bootstrap 0
[[ -f $marker ]]
! grep -q allow-idle "$WORK/home/idle-calls"
rm "$marker"
printf '#!/bin/bash\nexit 23\n' >"$REPO/2 Fonts.sh"
run_bootstrap 23
[[ ! -f $marker ]]
run_bootstrap 42 MOCK_IDLE_FAIL=1
! grep -q 'START Software' "$LOG"
[[ ! -f $marker ]]
printf '#!/bin/bash\nkill -TERM "$PPID"\nsleep 0.2\n' >"$REPO/2 Fonts.sh"
run_bootstrap 143
[[ ! -f $marker ]]
# macOS must not touch Omarchy even if an omarchy binary happens to be in PATH.
printf '#!/bin/sh\necho Darwin\n' >"$WORK/bin/uname"
printf '#!/bin/bash\nexit 0\n' >"$REPO/1 SoftwareInstall.sh"
printf '#!/bin/bash\nexit 0\n' >"$REPO/2 Fonts.sh"
: >"$WORK/home/idle-calls"
run_bootstrap 0
[[ ! -s "$WORK/home/idle-calls" ]]

printf 'bootstrap logging tests passed\n'
