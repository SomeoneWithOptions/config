#!/usr/bin/env bash

set -euo pipefail

# Usage: 4 ConfigFiles.sh [--check]
#
# Default: copy every managed config into ~ (idempotent, rerun any time).
# --check: write nothing. Print a unified diff for every managed target that
#          differs from the repo, then a count. The post-update hook runs this so
#          `omarchy update` migrations and other tools' edits are seen, not undone.

CHECK=0
case "${1:-}" in
    --check) CHECK=1 ;;
    "") ;;
    *) printf 'Usage: %s [--check]\n' "$0" >&2; exit 2 ;;
esac
DRIFT=0

OS_NAME=$(uname -s)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/report.sh
. "$SCRIPT_DIR/scripts/lib/report.sh"
# shellcheck source=scripts/lib/copy.sh
. "$SCRIPT_DIR/scripts/lib/copy.sh"
# shellcheck source=scripts/apply/dotfiles.sh
. "$SCRIPT_DIR/scripts/apply/dotfiles.sh"
# shellcheck source=scripts/apply/generated.sh
. "$SCRIPT_DIR/scripts/apply/generated.sh"
# shellcheck source=scripts/apply/settings.sh
. "$SCRIPT_DIR/scripts/apply/settings.sh"
# shellcheck source=scripts/apply/migrations.sh
. "$SCRIPT_DIR/scripts/apply/migrations.sh"

if (( CHECK )); then
    if (( DRIFT == 0 )); then
        printf 'No drift: every managed target matches the repo.\n'
    else
        printf '\n%d managed target(s) differ from the repo.\n' "$DRIFT"
        printf 'Apply repo state: bash "%s"   Or port the live changes into the repo.\n' "$SCRIPT_DIR/4 ConfigFiles.sh"
    fi
fi
