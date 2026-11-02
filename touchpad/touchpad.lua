-- Touchpad feel for the Latitude 9330, tuned by hand. Paste into
-- ~/.config/hypr/input.lua; Hyprland applies it as soon as you save.
--
-- Slow and normal movements always move the pointer the same amount (precise,
-- predictable), and only quick flicks get a boost, up to 6x. Only the built-in
-- touchpad is affected; external mice keep their usual settings.
--
-- To undo, delete this block.
hl.device({
  name = "ven_0488:00-0488:1038-touchpad",
  accel_profile = "custom 1 0 1 2 3 4 5 6.38 8.7 12.16 16.89 22.96 30.36 39 48.75 59.36 70.56 81.97 93.16 103.63 112.79 120 126 132 138 144 150 156 162 168 174 180 186 192 198 204 210 216 222 228 234 240",
})
