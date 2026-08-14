-- Keep terminals fully opaque.
o.window("^Alacritty$", { opacity = "1.0 override 1.0 override" })

-- Give btop enough room at fractional display scaling.
o.window([=[^org\.omarchy\.btop$]=], { size = { 1200, 800 }, center = true })

-- Keep 1Password tiled while retaining Omarchy's no-screen-share rule.
o.window("^1[Pp]assword$", { tag = "-floating-window", tile = true })

-- Movable Zen picture-in-picture.
o.window({ class = "^zen$", title = "^Picture-in-Picture$" }, {
  pin = false,
  border_size = 1,
  move = { "cursor_x-(window_w*0.5)", "cursor_y-(window_h*0.5)" },
})

-- Keep Zoom outside the tiling/group layout.
o.window([=[^([Zz]oom|zoom\.real)$]=], {
  float = true,
  group = "deny",
})
