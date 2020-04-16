animation { width = 300, height = 200, length = 1, framerate = 60 }

darkgray = solid(gray(32))
white = solid(gray(255))

sans = font("sans-serif")

HNames = { "Left", "Center", "Right" }
VNames = { "Top",  "Middle", "Bottom" }

function render()
  clear(darkgray)

  for hi, halign in ipairs({ taLeft, taCenter, taRight }) do
    for vi, valign in ipairs({ taTop, taMiddle, taBottom }) do
      local name = HNames[hi]..' '..VNames[vi]
      textf(sans, 0, 0, name, 12, white, width, height, halign, valign)
    end
  end
end
