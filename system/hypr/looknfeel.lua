-- Black top strip only; sides and bottom use the same gap as between windows.
hl.config({
  general = {
    gaps_out = 10,
    border_size = 0,
    resize_on_border = true,
  },
  decoration = {
    rounding = 18,
    rounding_power = 4.0,
  },
})

-- Omarchy disables workspace transitions by default.
hl.animation({
  leaf = "workspaces",
  enabled = true,
  speed = 5.5,
  bezier = "easeOutQuint",
  style = "slide",
})

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.
