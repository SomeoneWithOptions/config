#!/usr/bin/env bash
if pgrep -f "^gpu-screen-recorder" >/dev/null; then
  echo '{"text": "<span font=\x27Material Symbols Rounded 13 @FILL=1\x27>videocam</span>", "tooltip": "Stop recording", "class": "active"}'
else
  echo '{"text": ""}'
fi
