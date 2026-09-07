-- Personal bindings layered over Omarchy Quattro defaults.

-- Everything menu-ish lives on SUPER+SPACE. Drop Quattro's apps-menu shortcut
-- so there is only one way in.
hl.unbind("SUPER + ALT + SPACE")

-- SUPER+SHIFT+W stays on Quattro's default (Omawrite); typora is uninstalled here.
o.bind(
  "SUPER + SHIFT + H",
  "Herdr (Foot)",
  { launch = "foot --app-id=org.omarchy.herdr herdr", focus = "^org.omarchy.herdr$" }
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

-- Mac-style editing shortcuts, mirroring Omarchy's universal clipboard
-- (default/hypr/bindings/clipboard.lua) on ALT instead of SUPER.
--
-- Explicit mods via send_key_state keep the physically-held ALT from merging
-- into the injected chord at the seat, and the down/up split works around
-- Hyprland leaving synthetic key state stuck/repeating.
-- https://github.com/hyprwm/Hyprland/discussions/14099
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))

    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

-- Apps that want the terminal chord even though they aren't tagged `terminal`.
-- Zed embeds its own terminal emulator (no foot involved), and its vim mode
-- takes CTRL+C/CTRL+V in the editor pane, so both panes need the Insert chord.
-- Tagging Zed `terminal` would also hand it terminal theming, so match the
-- class here instead. Zed's keymap.json binds CTRL/SHIFT+Insert to copy/paste
-- in the Editor and Terminal contexts.
local insert_chord_classes = {
  ["dev.zed.Zed"] = true,
}

-- Otherwise lean on the `terminal` tag from default/hypr/apps/terminals.lua
-- rather than a second hardcoded class list that drifts out of sync. Dynamic
-- tags trail "*".
local function active_window_wants_insert_chord()
  local window = hl.get_active_window()

  if window and insert_chord_classes[window.class] then
    return true
  end

  for _, tag in ipairs(window and window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end

  return false
end

local function clipboard_shortcut(mods, key, terminal_mods, terminal_key)
  return function()
    if active_window_wants_insert_chord() then
      send_shortcut_once(terminal_mods, terminal_key)()
    else
      send_shortcut_once(mods, key)()
    end
  end
end

-- CTRL/SHIFT+Insert is the copy/paste chord terminals and TUIs agree on;
-- CTRL+SHIFT+C only works in the handful of terminals that bind it.
o.bind("ALT + C", "Copy", clipboard_shortcut("CTRL", "C", "CTRL", "Insert"))
o.bind("ALT + V", "Paste", clipboard_shortcut("CTRL", "V", "SHIFT", "Insert"))
o.bind("ALT + X", "Cut", send_shortcut_once("CTRL", "X"))
o.bind("ALT + Z", "Undo", send_shortcut_once("CTRL", "Z"))

-- Linear ticket capture. Toggles the andres.linear bar popup in place, so the
-- keybind and the bar icon land on the same panel rather than two surfaces.
o.bind("SUPER + SHIFT + L", "New Linear issue", "omarchy-shell andres.linear toggle")
