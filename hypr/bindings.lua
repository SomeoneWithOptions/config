-- Personal bindings layered over Omarchy Quattro defaults.

-- Everything menu-ish lives on SUPER+SPACE. Drop Quattro's apps-menu shortcut
-- so there is only one way in.
hl.unbind("SUPER + ALT + SPACE")

-- SUPER+SHIFT+W stays on Quattro's default (Omawrite); typora is uninstalled here.
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

-- Lean on the `terminal` tag from default/hypr/apps/terminals.lua rather than a
-- second hardcoded class list that drifts out of sync. Dynamic tags trail "*".
local function active_window_is_terminal()
  local window = hl.get_active_window()

  for _, tag in ipairs(window and window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end

  return false
end

local function clipboard_shortcut(mods, key, terminal_mods, terminal_key)
  return function()
    if active_window_is_terminal() then
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
