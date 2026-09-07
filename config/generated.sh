# Framed Omarchy panels are generated from the stock panels, so they are
# compared/regenerated rather than copied; also owns the shell restart that
# the regeneration requires.

if [[ "$OS_NAME" == "Linux" ]]; then
    framed_panels_changed=""
    if (( CHECK )); then
        # Generate into a scratch root and diff against the live plugins.
        framed_panels_tmp="$(mktemp -d)"
        if OMARCHY_CONFIG_ROOT="$framed_panels_tmp" python "$SCRIPT_DIR/omarchy/install-framed-panels.py" >/dev/null 2>&1; then
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
    elif ! framed_panels_changed=$(python "$SCRIPT_DIR/omarchy/install-framed-panels.py"); then
        report_warning 'Framed panel generation FAILED (upstream panel source changed).'
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -u critical "Config replay" "Framed panels failed to regenerate" || true
        fi
        framed_panels_changed=""
    fi
    if (( ! CHECK )); then
        if [[ -n "$framed_panels_changed" ]]; then
            printf 'Updated framed Omarchy panels\n'
            omarchy restart shell || true
        else
            omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
        fi
    fi
fi
