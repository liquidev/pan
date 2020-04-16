TrackLen = 96
SquareSize = 32
Spacing = { x = TrackLen + 32, y = SquareSize + 16 }

animation {
  width = 3 * Spacing.x + 32,
  height = 10 * Spacing.y + 48,
  length = 1,
  framerate = 25,
}

sans = font("sans-serif")

blue = solid(hex"02a9fc")
foreground = solid(gray(255))
background = solid(gray(255, 128))

function render()
  clear(blue)

  local x = 16
  for col, groupName in ipairs{"In", "Out", "InOut"} do
    local y = 10
    textf(sans, x, y, groupName, 14, foreground, 0, 0, taLeft)
    y = y + 32
    for _, funcName in ipairs{"sine", "quad", "cubic", "quartic", "quintic",
                              "expo", "circ", "back", "elastic", "bounce"} do
      if col == 1 then
        textf(sans, x, y + 6, funcName, 14, background)
      end
      local easing = Easings[groupName][funcName]
      rectf(ease(x, x + TrackLen - SquareSize, 0, 1, easing), y,
            SquareSize, SquareSize,
            foreground)
      y = y + Spacing.y
    end
    x = x + Spacing.x
  end
end
