#!/usr/bin/env bash
# Quickshell owns notifications while the desktop frame is on; mako otherwise.
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy
if [[ -e $state_dir/desktop-frame-off ]]; then
  silenced=$(makoctl mode 2>/dev/null | grep -q 'do-not-disturb' && echo 1 || echo 0)
else
  silenced=$(cat "$state_dir/notifications-silenced" 2>/dev/null || echo 0)
fi

if [[ $silenced == 1 ]]; then
  echo '{"text": "<span font=\x27Material Symbols Rounded 13 @FILL=1\x27>notifications_off</span>", "tooltip": "Notifications silenced", "class": "active"}'
else
  echo '{"text": ""}'
fi
