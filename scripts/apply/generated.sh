# Framed Omarchy panels are generated from the stock panels, so they are
# compared/regenerated rather than copied; also owns the shell restart that
# the regeneration requires. The framed notifications clone is copied here so
# Loom can reapply its rich-card overlay after rsync --delete.

loom_notifications_overlay() {
    local helper="" loom_bin="" source_root=""
    if command -v loom >/dev/null 2>&1; then
        loom_bin=$(command -v loom)
        helper=$(dirname "$(dirname "$(readlink -f "$loom_bin")")")/libexec/loom-notifications-overlay
        [[ -x $helper ]] && { printf '%s\n' "$helper"; return 0; }
    fi
    if [[ -f ${XDG_STATE_HOME:-$HOME/.local/state}/loom-omarchy-linux/install.json ]]; then
        source_root=$(jq -r '.sourceRoot // empty' \
          "${XDG_STATE_HOME:-$HOME/.local/state}/loom-omarchy-linux/install.json" 2>/dev/null || true)
        if [[ -n $source_root && -x $source_root/libexec/loom-notifications-overlay ]]; then
            printf '%s\n' "$source_root/libexec/loom-notifications-overlay"
            return 0
        fi
    fi
    helper=$HOME/.local/share/loom-omarchy-linux/libexec/loom-notifications-overlay
    [[ -x $helper ]] || return 1
    printf '%s\n' "$helper"
}

expected_notifications_tree() {
    local dest=$1 helper=""
    mkdir -p "$dest"
    cp -a "$SCRIPT_DIR/system/omarchy/plugins/andres.notifications/." "$dest/"
    helper=$(loom_notifications_overlay) || return 0
    # Hash mismatch leaves dest as the config baseline so --check reports drift
    # instead of aborting the whole replay.
    "$helper" apply --target "$dest" --no-restart --no-validate >/dev/null 2>&1 || true
}

if [[ "$OS_NAME" == "Linux" ]]; then
    framed_panels_changed=""
    notifications_changed=""
    notifications_src="$SCRIPT_DIR/system/omarchy/plugins/andres.notifications"
    notifications_live="$HOME/.config/omarchy/plugins/andres.notifications"
    if (( CHECK )); then
        # Generate into a scratch root and diff against the live plugins.
        framed_panels_tmp="$(mktemp -d)"
        if OMARCHY_CONFIG_ROOT="$framed_panels_tmp" python "$SCRIPT_DIR/system/omarchy/install-framed-panels.py" >/dev/null 2>&1; then
            for generated in "$framed_panels_tmp"/plugins/andres.*; do
                live="$HOME/.config/omarchy/plugins/$(basename "$generated")"
                if [[ ! -d "$live" ]] || ! diff -qr "$generated" "$live" >/dev/null 2>&1; then
                    report_drift "$live" "$generated"
                fi
            done
        else
            report_drift "framed panels" "" "generation FAILED (upstream panel source changed)"
        fi
        rm -rf "$framed_panels_tmp"

        notifications_expected="$(mktemp -d)"
        expected_notifications_tree "$notifications_expected"
        if [[ ! -d $notifications_live ]] || ! diff -qr "$notifications_expected" "$notifications_live" >/dev/null 2>&1; then
            report_drift "$notifications_live" "$notifications_expected"
        fi
        rm -rf "$notifications_expected"
    else
        if ! framed_panels_changed=$(python "$SCRIPT_DIR/system/omarchy/install-framed-panels.py"); then
            report_warning 'Framed panel generation FAILED (upstream panel source changed).'
            if command -v notify-send >/dev/null 2>&1; then
                notify-send -u critical "Config replay" "Framed panels failed to regenerate" || true
            fi
            framed_panels_changed=""
        fi

        notifications_expected="$(mktemp -d)"
        expected_notifications_tree "$notifications_expected"
        if [[ -d $notifications_live ]] && diff -qr "$notifications_expected" "$notifications_live" >/dev/null 2>&1; then
            rm -rf "$notifications_expected"
        else
            rm -rf "$notifications_expected"
            copy_dir_required "$notifications_src" "$notifications_live"
            overlay_helper=""
            if overlay_helper=$(loom_notifications_overlay); then
                overlay_status=0
                overlay_result=
                overlay_result=$("$overlay_helper" apply --target "$notifications_live" --no-restart) || overlay_status=$?
                if (( overlay_status == 0 )); then
                    if [[ $overlay_result == updated ]]; then
                        notifications_changed=1
                        printf 'Applied Loom recording-card overlay to %s\n' "$notifications_live"
                    fi
                elif (( overlay_status == 2 )); then
                    report_warning 'Notification clone is not the known framed baseline; Loom rich cards skipped.'
                else
                    report_warning 'Loom notification overlay helper failed; rich cards skipped.'
                fi
            else
                notifications_changed=1
            fi
        fi
    fi
    if (( ! CHECK )); then
        if [[ -n "$framed_panels_changed" || -n "$notifications_changed" ]]; then
            printf 'Updated framed Omarchy panels\n'
            omarchy restart shell || true
        else
            omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
        fi
    fi
fi
