#!/usr/bin/env bash
if pgrep -x hypridle >/dev/null; then
  echo '{"text": ""}'
else
  echo '{"text": "<span font=\x27Material Symbols Rounded 13 @FILL=1\x27>bedtime_off</span>", "tooltip": "Idle lock disabled", "class": "active"}'
fi
