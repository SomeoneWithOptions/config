# Selected laptop settings. CHECK must never write or call privileged commands.
# Filesystem roots are overridable for isolated tests, not user-specific paths.

copy_system_required() {
    local source=$1 target=$2
    cmp -s "$source" "$target" && return 0
    if (( CHECK )); then
        report_drift "$target" "$source"
    elif ! sudo install -D -m 644 "$source" "$target"; then
        report_warning "Could not install $target"
        return 1
    fi
}

if [[ "$OS_NAME" == Linux ]]; then
    power_supply_root=${CONFIG_POWER_SUPPLY_ROOT:-/sys/class/power_supply}
    battery_rule=${CONFIG_BATTERY_RULE:-/etc/udev/rules.d/99-battery-charge-threshold.rules}
    batteries=()
    for battery in "$power_supply_root"/BAT*; do
        [[ -f "$battery/charge_control_end_threshold" ]] || continue
        batteries+=("$battery")
    done
    if (( ${#batteries[@]} )); then
        if copy_system_required "$SCRIPT_DIR/system/udev/99-battery-charge-threshold.rules" "$battery_rule"; then
            if (( ! CHECK )); then
                sudo udevadm control --reload-rules
                for battery in "${batteries[@]}"; do
                    sudo udevadm trigger --action=add "$battery"
                done
                sudo udevadm settle
            fi
            for battery in "${batteries[@]}"; do
                for spec in end:90 start:85; do
                    control="${spec%:*}" wanted="${spec#*:}"
                    threshold="$battery/charge_control_${control}_threshold"
                    [[ -r "$threshold" ]] || continue
                    if [[ $(<"$threshold") != "$wanted" ]]; then
                        if (( CHECK )); then
                            report_drift "$threshold" "" "expected $wanted percent"
                        else
                            report_warning "$threshold did not accept $wanted percent; verify battery support"
                        fi
                    fi
                done
            done
        fi
    fi

    profile_state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/powerprofiles"
    if command -v powerprofilesctl >/dev/null 2>&1; then
        profiles_changed=0
        for preference in ac:balanced battery:power-saver; do
            mode=${preference%:*} wanted=${preference#*:}
            profile_file="$profile_state/$mode"
            actual=""
            [[ ! -r "$profile_file" ]] || actual=$(<"$profile_file")
            if [[ "$actual" != "$wanted" ]]; then
                if (( CHECK )); then
                    report_drift "$profile_file" "" "expected $wanted"
                elif omarchy powerprofiles set "$mode" "$wanted"; then
                    profiles_changed=1
                else
                    report_warning "Could not set $mode power profile to $wanted"
                fi
            fi
        done
        if (( ! CHECK && profiles_changed )); then
            omarchy powerprofiles set autodetect || report_warning 'Could not restore active power profile'
        fi
    fi

    backend_file="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/defaults/dictation"
    backend=""
    [[ ! -r "$backend_file" ]] || backend=$(<"$backend_file")
    if ! command -v superwhisper >/dev/null 2>&1; then
        if (( CHECK )); then
            report_drift superwhisper "" "missing; run software installer"
        else
            report_action superwhisper 'Superwhisper → install dictation' "Run: bash \"$SCRIPT_DIR/1 SoftwareInstall.sh\""
        fi
    elif (( CHECK )) && ! systemctl --user is-active --quiet superwhisper.service; then
        # Every superwhisper query starts the service, so a read-only check stops here.
        report_drift superwhisper.service "" "not active"
    else
        if (( ! CHECK )); then
            systemctl --user enable --now superwhisper.service || report_warning 'Could not enable Superwhisper'
        elif ! systemctl --user is-enabled --quiet superwhisper.service; then
            report_drift superwhisper.service "" "not enabled"
        fi
        if [[ "$backend" != superwhisper ]]; then
            if (( CHECK )); then
                report_drift "$backend_file" "" "expected superwhisper"
            else
                omarchy dictation use superwhisper || report_warning 'Could not select Superwhisper'
            fi
        fi
        superwhisper_state=$(superwhisper models show 2>/dev/null || true)
        if [[ $(jq -r '.processing // ""' <<<"$superwhisper_state" 2>/dev/null) != offline ]]; then
            if (( CHECK )); then
                report_drift superwhisper "" "processing mode is not offline"
            elif jq -e '.processingModes[]? | select(.value == "offline" and (.missing | length) == 0)' \
                <<<"$superwhisper_state" >/dev/null 2>&1; then
                superwhisper models select offline >/dev/null || report_warning 'Could not select Superwhisper offline mode'
            else
                report_action superwhisper-models 'Superwhisper → download offline models' "Run: bash \"$SCRIPT_DIR/1 SoftwareInstall.sh\""
            fi
        fi
        declare -A superwhisper_shown=()
        while read -r section key value; do
            [[ -n "$section" && "$section" != \#* ]] || continue
            [[ -v "superwhisper_shown[$section]" ]] ||
                superwhisper_shown[$section]=$(superwhisper "$section" show 2>/dev/null || true)
            if [[ "$section" == shortcuts ]]; then
                wanted=$value
                [[ "$wanted" != none ]] || wanted=""
                filter='(.shortcuts[$key] // "") == $wanted'
                jq_args=(--arg wanted "$wanted")
            else
                filter='getpath(["config"] + ($key | split("."))) == $wanted'
                jq_args=(--argjson wanted "$value")
            fi
            jq -e --arg key "$key" "${jq_args[@]}" "$filter" <<<"${superwhisper_shown[$section]}" >/dev/null 2>&1 && continue
            if (( CHECK )); then
                report_drift "superwhisper $section $key" "" "expected $value"
            elif ! superwhisper "$section" set "$key" "$value" >/dev/null; then
                report_warning "Could not set Superwhisper $section $key"
            fi
        done <"$SCRIPT_DIR/apps/superwhisper/settings"
    fi
fi
