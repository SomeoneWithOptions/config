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
! grep -q 'OMARCHY_ALLOW_DIRECT_PACMAN' "$ROOT/scripts/install/arch.sh"
! grep -Eq 'pacman[[:space:]]+-S(yu|uy)|pacman[[:space:]]+-Syu' "$ROOT/scripts/install/arch.sh"

# --- App-by-app progress events ---------------------------------------------
# Each block builds a fresh mock environment; every installer is hermetic.

soft_new_env() {
  SOFT=$(mktemp -d)
  mkdir -p "$SOFT/bin" "$SOFT/home" "$SOFT/report/actions" "$SOFT/report/stages"
  : >"$SOFT/calls"
  : >"$SOFT/report/warnings"
  : >"$SOFT/software-events"
  cat >"$SOFT/bin/uname" <<'SH'
#!/bin/sh
echo "${SOFT_UNAME:-Linux}"
SH
  cat >"$SOFT/bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$MOCK_CALLS"
if [ "$1" = -Q ]; then
  case " ${MOCK_INSTALLED:-} " in *" $2 "*) exit 0 ;; esac
  exit 1
fi
if [ "$1" = -Si ]; then
  case " ${MOCK_NOT_IN_REPO:-} " in *" $2 "*) exit 1 ;; esac
  exit 0
fi
exit 99
SH
  cat >"$SOFT/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$MOCK_CALLS"
case "$1 $2" in
  'pacman -S')
    case " ${MOCK_FAIL_PACKAGES:-} " in *" ${*: -1} "*) exit 1 ;; esac
    ;;
esac
exit 0
SH
  cat >"$SOFT/bin/omarchy" <<'SH'
#!/bin/bash
printf 'omarchy %s\n' "$*" >>"$MOCK_CALLS"
state="$SOFT_STATE_DIR/editor"
if [ "$1 $2" = 'default editor' ]; then
  if [ -n "${3:-}" ]; then printf '%s\n' "$3" >"$state"; fi
  cat "$state" 2>/dev/null
  exit 0
fi
if [ "$1 $2" = 'update -y' ]; then
  [ "${MOCK_UPDATE_FAIL:-0}" = 1 ] && exit 42
  exit 0
fi
if [ "$1 $2" = 'pkg add' ]; then
  case " ${MOCK_FAIL_PKG_ADD:-} " in *" $3 "*) exit 1 ;; esac
fi
exit 0
SH
  for tool in mise omarchy-mise-install omarchy-webapp-install systemctl pi clasp vercel rtk brew yay; do
    printf '#!/bin/sh\nprintf "%s %%s\\n" "%s" "$*" >>"$MOCK_CALLS"\nexit 0\n' "$tool" "$tool" >"$SOFT/bin/$tool"
  done
  cat >"$SOFT/bin/turso" <<'SH'
#!/bin/sh
printf 'turso %s\n' "$*" >>"$MOCK_CALLS"
[ "$1" = whoami ] && exit "${MOCK_TURSO_STATUS:-0}"
exit 0
SH
  cat >"$SOFT/bin/brew" <<'SH'
#!/bin/bash
printf 'brew %s\n' "$*" >>"$MOCK_CALLS"
case "$1 $2" in
  'list --formula'|'list --cask')
    case " ${MOCK_INSTALLED:-} " in *" $3 "*) exit 0 ;; esac
    exit 1
    ;;
esac
case "$1" in
  '--prefix') echo "${MOCK_CALLS%/calls}/prefix" ;;
esac
exit 0
SH
  cat >"$SOFT/bin/yay" <<'SH'
#!/bin/sh
printf 'yay %s\n' "$*" >>"$MOCK_CALLS"
exit "${MOCK_YAY_STATUS:-0}"
SH
  cat >"$SOFT/bin/tailscale" <<'SH'
#!/bin/sh
printf 'tailscale %s\n' "$*" >>"$MOCK_CALLS"
[ "$1" = status ] && exit "${MOCK_TAILSCALE_STATUS:-1}"
exit 0
SH
  cat >"$SOFT/bin/curl" <<'SH'
#!/bin/sh
printf 'curl %s\n' "$*" >>"$MOCK_CALLS"
exit "${MOCK_CURL_STATUS:-0}"
SH
  chmod +x "$SOFT/bin/"*
}

soft_run() {
  status=0
  env HOME="$SOFT/home" PATH="$SOFT/bin:/usr/bin:/bin" MOCK_CALLS="$SOFT/calls" \
    SOFT_STATE_DIR="$SOFT" BOOTSTRAP_REPORT_DIR="$SOFT/report" BOOTSTRAP_STAGE=software \
    BOOTSTRAP_SOFTWARE_PROGRESS_FILE="$SOFT/software-events" \
    OMARCHY_UPDATE_LOG_FILE="$SOFT/omarchy-update.log" \
    bash "$ROOT/1 SoftwareInstall.sh" >"$SOFT/output" 2>&1 || status=$?
}

soft_assert_no_done_after_fail() {
  # Within one operation, a fail record must never be followed by done.
  python3 - "$SOFT/software-events" <<'PY'
import sys
ops = {}
for line in open(sys.argv[1]):
    state, _, label = line.rstrip("\n").partition("\t")
    ops.setdefault(label, []).append(state)
for label, states in ops.items():
    assert "fail" not in states or "done" not in states, (label, states)
PY
}

# set -e exempts negated commands, so absence is asserted explicitly.
soft_assert_absent() {
  local pattern=$1 file=$2
  if grep -q -- "$pattern" "$file" 2>/dev/null; then
    printf 'unexpected %s in %s\n' "$pattern" "$file" >&2
    exit 1
  fi
}

# Omarchy: everything mocked green. Events must track the real operation
# order: update first, then removal, then per-package installs.
soft_new_env
MOCK_INSTALLED='zed omazed 1password 1password-cli'
# turso-cli-bin only exists in the AUR, so it must take the yay path.
MOCK_NOT_IN_REPO='turso-cli-bin'
export MOCK_INSTALLED MOCK_NOT_IN_REPO
status=0
soft_run
[[ $status == 0 ]]
[[ ! -s "$SOFT/report/warnings" ]]
[[ $(head -n1 "$SOFT/software-events") == $'start\tUpdating Omarchy and system packages…' ]]
[[ $(sed -n 2p "$SOFT/software-events") == $'done\tOmarchy and system packages updated' ]]
grep -q $'start\tRemoving stock Omarchy apps…' "$SOFT/software-events"
grep -q $'done\tStock Omarchy apps removed' "$SOFT/software-events"
grep -q $'start\tInstalling fish…' "$SOFT/software-events"
grep -q $'done\tfish installed' "$SOFT/software-events"
grep -q $'start\tInstalling Node.js…' "$SOFT/software-events"
grep -q $'done\tNode.js installed' "$SOFT/software-events"
grep -q $'start\tInstalling Go…' "$SOFT/software-events"
grep -q $'done\tGo installed' "$SOFT/software-events"
grep -q $'skip\tZed already installed' "$SOFT/software-events"
grep -q $'start\tInstalling Zen browser…' "$SOFT/software-events"
grep -q $'done\tZen browser installed' "$SOFT/software-events"
grep -q $'start\tInstalling Tailscale…' "$SOFT/software-events"
grep -q $'done\tTailscale installed' "$SOFT/software-events"
grep -q $'start\tConfiguring Tailscale…' "$SOFT/software-events"
grep -q $'done\tTailscale configured' "$SOFT/software-events"
grep -q $'start\tConfiguring 1Password…' "$SOFT/software-events"
grep -q $'done\t1Password configured' "$SOFT/software-events"
grep -q $'done\tcommiter installed' "$SOFT/software-events"
grep -q $'done\tclasp installed' "$SOFT/software-events"
grep -q $'done\tloom-omarchy-linux installed' "$SOFT/software-events"
grep -q $'done\tlinear-omarchy-plugin installed' "$SOFT/software-events"
grep -q $'done\tturso-cli-bin installed' "$SOFT/software-events"
! grep -q $'fail' "$SOFT/software-events"
# Package work only after the successful update.
[[ $(grep -n '^omarchy update -y$' "$SOFT/calls" | head -1 | cut -d: -f1) -lt \
  $(grep -n '^sudo pacman ' "$SOFT/calls" | head -1 | cut -d: -f1) ]]
grep -q '^sudo pacman -S --needed --noconfirm fish$' "$SOFT/calls"
grep -q '^sudo pacman -S --needed --noconfirm herdr$' "$SOFT/calls"
grep -q '^yay -S --needed --noconfirm turso-cli-bin$' "$SOFT/calls"
rm -rf "$SOFT"
unset MOCK_INSTALLED MOCK_NOT_IN_REPO

# Omarchy: everything already installed reports skip where detection exists
# and runs no package installers.
soft_new_env
MOCK_INSTALLED='fish alacritty ghostty herdr vim terraform aws-cli-v2 google-cloud-cli bind fwupd cmatrix vlc gsfonts ttf-liberation libfprint fprintd usbutils libcamera libcamera-ipa libcamera-tools pipewire-libcamera gst-plugin-libcamera v4l2loopback-dkms zed omazed zen-browser-bin tailscale 1password 1password-cli turso-cli-bin'
# turso whoami fails, so the sign-in follow-up note must be written.
MOCK_TURSO_STATUS=1
export MOCK_INSTALLED MOCK_TURSO_STATUS
printf '#!/bin/sh\nexit 0\n' >"$SOFT/bin/loom"
chmod +x "$SOFT/bin/loom"
mkdir -p "$SOFT/home/.local/bin"
touch "$SOFT/home/.local/bin/c"
chmod +x "$SOFT/home/.local/bin/c"
mkdir -p "$SOFT/home/.config/omarchy/plugins/andres.linear/bin"
printf '{}' >"$SOFT/home/.config/omarchy/plugins/andres.linear/manifest.json"
printf '#!/bin/sh\nexit 99\n' >"$SOFT/home/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup"
chmod +x "$SOFT/home/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup"
soft_run
[[ $status == 0 ]]
grep -q $'skip\tfish already installed' "$SOFT/software-events"
grep -q $'skip\therdr already installed' "$SOFT/software-events"
grep -q $'skip\tZed already installed' "$SOFT/software-events"
grep -q $'start\tConfiguring Zen browser…' "$SOFT/software-events"
grep -q $'done\tZen browser configured' "$SOFT/software-events"
grep -q $'skip\tTailscale already installed' "$SOFT/software-events"
grep -q $'start\tConfiguring 1Password…' "$SOFT/software-events"
grep -q $'done\t1Password configured' "$SOFT/software-events"
grep -q $'skip\trtk already installed' "$SOFT/software-events"
grep -q $'skip\tcommiter already installed' "$SOFT/software-events"
grep -q $'done\tclasp installed' "$SOFT/software-events"
grep -q $'skip\tloom-omarchy-linux already installed' "$SOFT/software-events"
grep -q $'skip\tlinear-omarchy-plugin already installed' "$SOFT/software-events"
grep -q $'skip\tturso-cli-bin already installed' "$SOFT/software-events"
grep -q 'Turso CLI → sign in' "$SOFT/report/actions/turso"
grep -q 'Run: turso auth login' "$SOFT/report/actions/turso"
grep -q $'start\tConfiguring Tailscale…' "$SOFT/software-events"
grep -q $'done\tTailscale configured' "$SOFT/software-events"
! grep -q '^sudo pacman -S ' "$SOFT/calls"
! grep -q '^pacman -Si ' "$SOFT/calls"
rm -rf "$SOFT"
unset MOCK_INSTALLED MOCK_TURSO_STATUS

# Omarchy: a failing optional package warns and reports failure, later packages
# continue, and no success is ever claimed for the failed operation.
soft_new_env
MOCK_FAIL_PACKAGES='fish'
MOCK_NOT_IN_REPO='libfprint turso-cli-bin'
MOCK_YAY_STATUS=1
export MOCK_FAIL_PACKAGES MOCK_NOT_IN_REPO MOCK_YAY_STATUS
soft_run
[[ $status == 0 ]]
grep -q $'fail\tfish installation failed' "$SOFT/software-events"
! grep -q $'done\tfish installed' "$SOFT/software-events"
grep -q $'fail\tlibfprint installation failed' "$SOFT/software-events"
grep -q $'done\tvim installed' "$SOFT/software-events"
grep -q 'pacman install fish failed.' "$SOFT/report/warnings"
grep -q 'yay install libfprint failed.' "$SOFT/report/warnings"
grep -q $'fail\tturso-cli-bin installation failed' "$SOFT/software-events"
grep -q 'yay install turso-cli-bin failed.' "$SOFT/report/warnings"
soft_assert_no_done_after_fail
rm -rf "$SOFT"
unset MOCK_FAIL_PACKAGES MOCK_NOT_IN_REPO MOCK_YAY_STATUS

# Omarchy: a failed Tailscale package install must skip all Tailscale
# configuration (no service/webapp/tailscale calls) while later optional work
# continues, because progress_step reports the command failure explicitly.
soft_new_env
MOCK_FAIL_PKG_ADD=tailscale
export MOCK_FAIL_PKG_ADD
soft_run
[[ $status == 0 ]]
grep -q $'start\tInstalling Tailscale…' "$SOFT/software-events"
grep -q $'fail\tTailscale installation failed' "$SOFT/software-events"
soft_assert_absent 'Configuring Tailscale' "$SOFT/software-events"
soft_assert_absent $'done\tTailscale' "$SOFT/software-events"
soft_assert_absent '^systemctl ' "$SOFT/calls"
soft_assert_absent '^sudo tailscale ' "$SOFT/calls"
soft_assert_absent '^tailscale ' "$SOFT/calls"
soft_assert_absent 'omarchy-webapp-install' "$SOFT/calls"
grep -q $'done\t1Password installed' "$SOFT/software-events"
grep -q $'done\tcommiter installed' "$SOFT/software-events"
grep -q 'omarchy install tailscale package failed.' "$SOFT/report/warnings"
soft_assert_no_done_after_fail
rm -rf "$SOFT"
unset MOCK_FAIL_PKG_ADD

# Omarchy: a package missing from the repos with no yay warns and reports
# failure. PATH excludes /usr/bin so the real yay binary is never consulted.
soft_new_env
MOCK_NOT_IN_REPO='libfprint'
export MOCK_NOT_IN_REPO
mkdir -p "$SOFT/core"
ln -s /usr/bin/date "$SOFT/core/date"
ln -s /usr/bin/tee "$SOFT/core/tee"
ln -s /usr/bin/bash "$SOFT/core/bash"
ln -s /usr/bin/dirname "$SOFT/core/dirname"
ln -s /usr/bin/chmod "$SOFT/core/chmod"
rm "$SOFT/bin/yay"
status=0
env HOME="$SOFT/home" PATH="$SOFT/bin:$SOFT/core" MOCK_CALLS="$SOFT/calls" \
  SOFT_STATE_DIR="$SOFT" BOOTSTRAP_REPORT_DIR="$SOFT/report" BOOTSTRAP_STAGE=software \
  BOOTSTRAP_SOFTWARE_PROGRESS_FILE="$SOFT/software-events" \
  OMARCHY_UPDATE_LOG_FILE="$SOFT/omarchy-update.log" \
  bash "$ROOT/1 SoftwareInstall.sh" >"$SOFT/output" 2>&1 || status=$?
[[ $status == 0 ]]
grep -q 'Cannot install libfprint: package unavailable and yay not found.' "$SOFT/output"
grep -q $'fail\tlibfprint installation failed' "$SOFT/software-events"
grep -q $'done\tvim installed' "$SOFT/software-events"
rm -rf "$SOFT"
unset MOCK_NOT_IN_REPO

# Omarchy: failed system update emits a fail event, never a done event, and
# still stops all package operations (exit 42 regression).
soft_new_env
MOCK_UPDATE_FAIL=1
export MOCK_UPDATE_FAIL
soft_run
[[ $status == 42 ]]
[[ $(wc -l <"$SOFT/software-events") == 2 ]]
[[ $(head -n1 "$SOFT/software-events") == $'start\tUpdating Omarchy and system packages…' ]]
grep -q $'fail\tOmarchy system update failed' "$SOFT/software-events"
! grep -q $'done\t' "$SOFT/software-events"
! grep -q '^pacman ' "$SOFT/calls"
rm -rf "$SOFT"
unset MOCK_UPDATE_FAIL

# Shell-pipeline installer: a failed curl must fail the pipeline under
# pipefail, emit a fail record, and never a done record for that operation.
soft_new_env
MOCK_CURL_STATUS=1
export MOCK_CURL_STATUS
soft_run
[[ $status == 0 ]]
grep -q $'fail\tcommiter installation failed' "$SOFT/software-events"
! grep -q $'done\tcommiter installed' "$SOFT/software-events"
grep -q 'commiter installer failed.' "$SOFT/report/warnings"
grep -q $'done\tclasp installed' "$SOFT/software-events"
soft_assert_no_done_after_fail
rm -rf "$SOFT"
unset MOCK_CURL_STATUS

# macOS: Homebrew formulas and casks with friendly app names.
soft_new_env
SOFT_UNAME=Darwin
export SOFT_UNAME
MOCK_INSTALLED='git gh tmux fish vim mise alacritty ghostty'
export MOCK_INSTALLED
soft_run
[[ $status == 0 ]]
grep -q $'skip\tHomebrew already installed' "$SOFT/software-events"
grep -q $'start\tUpdating Homebrew…' "$SOFT/software-events"
grep -q $'done\tHomebrew updated' "$SOFT/software-events"
grep -q $'skip\tgit already installed' "$SOFT/software-events"
grep -q $'done\t1password-cli installed' "$SOFT/software-events"
grep -q $'done\tNode.js 24 configured' "$SOFT/software-events"
grep -q $'done\tGo installed' "$SOFT/software-events"
grep -q $'start\tInstalling Zed…' "$SOFT/software-events"
grep -q $'done\tZed installed' "$SOFT/software-events"
grep -q $'done\t1Password installed' "$SOFT/software-events"
grep -q $'done\tcommiter installed' "$SOFT/software-events"
grep -q $'skip\tpi already installed' "$SOFT/software-events"
grep -q $'skip\tclasp already installed' "$SOFT/software-events"
grep -q '^brew install tursodatabase/tap/turso$' "$SOFT/calls"
grep -q $'done\tturso installed' "$SOFT/software-events"
! grep -q $'fail' "$SOFT/software-events"
rm -rf "$SOFT"
unset MOCK_INSTALLED SOFT_UNAME

# macOS: a failed Homebrew installer reports failure and never success. curl
# emits a failing script because the installer runs inside command substitution.
soft_new_env
rm "$SOFT/bin/brew"
SOFT_UNAME=Darwin
export SOFT_UNAME
cat >"$SOFT/bin/curl" <<'SH'
#!/bin/sh
printf 'curl %s\n' "$*" >>"$MOCK_CALLS"
printf 'exit 9\n'
SH
chmod +x "$SOFT/bin/curl"
soft_run
[[ $status == 0 ]]
grep -q $'fail\tHomebrew installation failed' "$SOFT/software-events"
! grep -q $'done\tHomebrew' "$SOFT/software-events"
grep -q 'Homebrew installer failed.' "$SOFT/report/warnings"
! grep -q '^brew ' "$SOFT/calls"
rm -rf "$SOFT"
unset SOFT_UNAME

# macOS: a hermetic Homebrew installer success path. The mocked curl output
# (run by /bin/bash -c) drops a stub brew onto the test PATH, so no host
# installation happens and the done event must be emitted after brew verifies.
soft_new_env
rm "$SOFT/bin/brew"
SOFT_UNAME=Darwin
export SOFT_UNAME
cat >"$SOFT/bin/brew-template" <<'SH'
#!/bin/bash
printf 'brew %s\n' "$*" >>"$MOCK_CALLS"
case "$1 $2" in
  'list --formula'|'list --cask')
    case " ${MOCK_INSTALLED:-} " in *" $3 "*) exit 0 ;; esac
    exit 1
    ;;
esac
case "$1" in
  '--prefix') echo "${MOCK_CALLS%/calls}/prefix" ;;
esac
exit 0
SH
cat >"$SOFT/bin/curl" <<SH
#!/bin/sh
printf 'curl %s\n' "\$*" >>"\$MOCK_CALLS"
cp "$SOFT/bin/brew-template" "$SOFT/bin/brew"
exit 0
SH
chmod +x "$SOFT/bin/curl" "$SOFT/bin/brew-template"
soft_run
[[ $status == 0 ]]
grep -q $'start\tInstalling Homebrew…' "$SOFT/software-events"
grep -q $'done\tHomebrew installed' "$SOFT/software-events"
! grep -q $'skip\tHomebrew already installed' "$SOFT/software-events"
! grep -q $'fail\tHomebrew' "$SOFT/software-events"
grep -q '^curl ' "$SOFT/calls"
grep -q '^brew update$' "$SOFT/calls"
grep -q $'start\tUpdating Homebrew…' "$SOFT/software-events"
rm -rf "$SOFT"
unset SOFT_UNAME

# report_software_progress: validation, TSV records, readable stdout.
HELPER=$(mktemp -d)
: >"$HELPER/events"
printf '#!/bin/bash\n. "$1/scripts/lib/report.sh"\nreport_software_progress "$2" "$3"\n' >"$HELPER/probe.sh"
chmod +x "$HELPER/probe.sh"
probe_progress() {
  local status=0
  env -u BOOTSTRAP_SOFTWARE_PROGRESS_FILE bash "$HELPER/probe.sh" "$ROOT" "$1" "$2" \
    >"$HELPER/out" 2>&1 || status=$?
  printf '%s' "$status"
}
[[ $(probe_progress start 'Installing Zen browser…') == 0 ]]
grep -q '→ Installing Zen browser…' "$HELPER/out"
[[ $(probe_progress done 'Zen browser installed') == 0 ]]
grep -q '✓ Zen browser installed' "$HELPER/out"
[[ $(probe_progress skip 'Zed already installed') == 0 ]]
grep -q '– Zed already installed' "$HELPER/out"
[[ $(probe_progress fail 'Zen browser installation failed') == 0 ]]
grep -q '! Zen browser installation failed' "$HELPER/out"
[[ $(probe_progress bogus 'Zen browser installation failed') == 2 ]]
grep -q 'invalid state: bogus' "$HELPER/out"
[[ $(probe_progress start '') == 2 ]]
[[ $(probe_progress start $'zen\tbad') == 2 ]]
grep -q 'without tabs or newlines' "$HELPER/out"
[[ $(probe_progress start $'zen\nbad') == 2 ]]
(
  export BOOTSTRAP_SOFTWARE_PROGRESS_FILE="$HELPER/events"
  . "$ROOT/scripts/lib/report.sh"
  report_software_progress start 'Installing Zen browser…'
  report_software_progress done 'Zen browser installed'
) >/dev/null
printf 'start\tInstalling Zen browser…\ndone\tZen browser installed\n' >"$HELPER/expected"
cmp "$HELPER/events" "$HELPER/expected"
: >"$HELPER/events"
env BOOTSTRAP_SOFTWARE_PROGRESS_FILE="$HELPER/events" bash "$HELPER/probe.sh" "$ROOT" bogus x \
  >/dev/null 2>&1 || true
[[ ! -s "$HELPER/events" ]]
rm -rf "$HELPER"

printf 'software update tests passed\n'
