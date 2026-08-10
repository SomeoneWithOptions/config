#!/usr/bin/env bash
if makoctl mode 2>/dev/null | grep -q 'do-not-disturb'; then
  echo '{"text": "<span font=\x27Material Symbols Rounded 13 @FILL=1\x27>notifications_off</span>", "tooltip": "Notifications silenced", "class": "active"}'
else
  echo '{"text": ""}'
fi
