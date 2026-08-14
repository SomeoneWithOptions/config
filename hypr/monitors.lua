-- Preserve this Lenovo panel and BenQ 4K layout across the Quattro migration.
hl.env("GDK_SCALE", "1")

hl.monitor({
  output = "desc:Lenovo Group Limited NV160WUM-N4E",
  mode = "1920x1200@60",
  position = "0x0",
  scale = 1.2,
})

hl.monitor({
  output = "desc:BNQ BenQ MA320U ET27S01282SL0",
  mode = "3840x2160@60",
  position = "auto",
  scale = 1.5,
})

-- Any unknown external display.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
