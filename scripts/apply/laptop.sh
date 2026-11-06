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

    backend_file="$HOME/.config/omarchy/defaults/dictation"
    backend=""
    [[ ! -r "$backend_file" ]] || backend=$(<"$backend_file")
    if [[ "$backend" != voxtype ]]; then
        if (( CHECK )); then
            report_drift "$backend_file" "" "expected voxtype"
        elif command -v voxtype >/dev/null 2>&1; then
            omarchy dictation use voxtype || report_warning 'Could not select Voxtype'
        fi
    fi
    if (( CHECK )); then
        for state in enabled active; do
            if ! systemctl --user "is-$state" --quiet voxtype.service; then
                report_drift voxtype.service "" "not $state"
            fi
        done
        model="${XDG_DATA_HOME:-$HOME/.local/share}/voxtype/models/ggml-medium.bin"
        [[ -s "$model" ]] || report_drift "$model" "" "missing Whisper medium model; run software installer"
        command -v voxtype >/dev/null 2>&1 || report_drift voxtype "" "missing; run software installer"
    elif command -v voxtype >/dev/null 2>&1; then
        systemctl --user daemon-reload
        systemctl --user enable --now voxtype.service || report_warning 'Could not enable Voxtype'
    else
        report_action voxtype 'Voxtype → install engine and model' "Run: bash \"$SCRIPT_DIR/1 SoftwareInstall.sh\""
    fi
fi
