-- Flush black desktop frame with squircle window corners.
hl.config({
  general = {
    gaps_out = 0,
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
