#!/usr/bin/env bash

set -euo pipefail

profile=$(powerprofilesctl get 2>/dev/null || echo balanced)

# Prefer UPower for readable battery state/capacity; fall back to /sys.
battery_path=$(upower -e 2>/dev/null | grep -m1 'BAT' || true)
if [[ -n "${battery_path}" ]]; then
  info=$(upower -i "$battery_path" 2>/dev/null || true)
  capacity=$(awk '/percentage:/ {gsub("%", "", $2); print int($2)}' <<<"$info")
  state=$(awk '/state:/ {print $2}' <<<"$info")
  rate=$(awk '/energy-rate:/ {print $2"W"}' <<<"$info")
else
  bat_dir=$(find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' | head -n1 || true)
  capacity=$(cat "$bat_dir/capacity" 2>/dev/null || echo 0)
  state=$(tr '[:upper:]' '[:lower:]' < "$bat_dir/status" 2>/dev/null || echo unknown)
  rate=""
fi

capacity=${capacity:-0}

if [[ "$capacity" -ge 95 ]]; then icon="battery_android_full"
elif [[ "$capacity" -ge 80 ]]; then icon="battery_android_6"
elif [[ "$capacity" -ge 65 ]]; then icon="battery_android_5"
elif [[ "$capacity" -ge 50 ]]; then icon="battery_android_4"
elif [[ "$capacity" -ge 35 ]]; then icon="battery_android_3"
elif [[ "$capacity" -ge 20 ]]; then icon="battery_android_2"
elif [[ "$capacity" -ge 10 ]]; then icon="battery_android_1"
else icon="battery_android_0"
fi

case "$profile" in
  power-saver) class="power-saver"; label="Battery saver" ;;
  performance) class="performance"; label="Performance" ;;
  balanced|*) class="balanced"; label="Balanced" ;;
esac

state_label=$(tr '-' ' ' <<<"${state:-unknown}")
tooltip="$label • ${capacity}%"
[[ -n "${rate:-}" ]] && tooltip="$tooltip • $rate"
[[ -n "${state_label:-}" ]] && tooltip="$tooltip • $state_label"

# Separate sizes and baseline offsets center both glyphs optically inside the pill.
printf '{"text":"<span font=\x27Material Symbols Rounded 12 @FILL=1\x27 rise=\x27-1200\x27>%s</span> <span rise=\x27600\x27>%s%%</span>","class":"%s","tooltip":"%s"}\n' "$icon" "$capacity" "$class" "$tooltip"
