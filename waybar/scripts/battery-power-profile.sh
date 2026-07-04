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

if [[ "$state" == "charging" ]]; then
  icons=(󰢜 󰂆 󰂇 󰂈 󰢝 󰂉 󰢞 󰂊 󰂋 󰂅)
elif [[ "$state" == "fully-charged" || "$state" == "full" ]]; then
  icons=(󰂅 󰂅 󰂅 󰂅 󰂅 󰂅 󰂅 󰂅 󰂅 󰂅)
else
  icons=(󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)
fi
idx=$(( capacity / 10 ))
(( idx > 9 )) && idx=9
icon=${icons[$idx]}
[[ "$state" == "fully-charged" || "$state" == "full" ]] && icon="󰂅"
[[ "$state" == "charging" && "$capacity" -ge 100 ]] && icon="󰂅"

case "$profile" in
  power-saver) class="power-saver"; label="Battery saver" ;;
  performance) class="performance"; label="Performance" ;;
  balanced|*) class="balanced"; label="Balanced" ;;
esac

state_label=$(tr '-' ' ' <<<"${state:-unknown}")
tooltip="$label • ${capacity}%"
[[ -n "${rate:-}" ]] && tooltip="$tooltip • $rate"
[[ -n "${state_label:-}" ]] && tooltip="$tooltip • $state_label"

printf '{"text":"%s%% %s","class":"%s","tooltip":"%s"}\n' "$capacity" "$icon" "$class" "$tooltip"
