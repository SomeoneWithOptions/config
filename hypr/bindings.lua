-- Personal bindings layered over Omarchy Quattro defaults.

-- Keep the custom app launcher on SUPER+SPACE and the Omarchy root/settings
-- menu on SUPER+ALT+SPACE, matching this machine's pre-Quattro behavior.
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "Launch apps", "omarchy-shell shell toggle andres.desktop-frame '{}'")
hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + ALT + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Preserve Typora and btop shortcuts.
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "Typora", "uwsm-app -- typora --enable-wayland-ime")
o.bind(
  "SUPER + SHIFT + H",
  "System monitor (btop)",
  "omarchy-launch-or-focus org.omarchy.btop 'alacritty --class org.omarchy.btop,org.omarchy.btop -e btop'"
)

-- Gamma controls remain separate from Quattro's normal brightness keys.
o.bind("CTRL + XF86MonBrightnessDown", "Gamma brightness down", "~/.local/bin/hyprsunset-gamma-display -10", { repeating = true, locked = true })
o.bind("CTRL + XF86MonBrightnessUp", "Gamma brightness up", "~/.local/bin/hyprsunset-gamma-display +10", { repeating = true, locked = true })

-- Letter workspaces replace fullscreen/copy/scratchpad and three app shortcuts.
for _, keys in ipairs({
  "SUPER + F", "SUPER + C", "SUPER + S",
  "SUPER + SHIFT + F", "SUPER + SHIFT + C", "SUPER + SHIFT + S",
}) do
  hl.unbind(keys)
end

for _, name in ipairs({ "F", "C", "S" }) do
  o.bind("SUPER + " .. name, "Switch to workspace " .. name, hl.dsp.focus({ workspace = "name:" .. name }))
  o.bind(
    "SUPER + SHIFT + " .. name,
    "Move window to workspace " .. name,
    hl.dsp.window.move({ workspace = "name:" .. name, follow = true })
  )
end

-- Screenshot saved and copied as a GNOME file object.
hl.unbind("PRINT")
o.bind("PRINT", "Screenshot copied as file", "~/.local/bin/omarchy-screenshot-file-clipboard")

-- Mac-style editing shortcuts.
o.bind("ALT + Z", "Undo", hl.dsp.send_shortcut({ mods = "CTRL", key = "Z" }))
o.bind("ALT + X", "Cut", hl.dsp.send_shortcut({ mods = "CTRL", key = "X" }))
o.bind("ALT + C", "Copy", "~/.local/bin/alt-edit-shortcut copy")
o.bind("ALT + V", "Paste", "~/.local/bin/alt-edit-shortcut paste")
