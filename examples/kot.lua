animation { width = 300, height = 300, length = 2, framerate = 25 }

local black = solid(hex"#000000")
local kot = image.load("kot.png")

function render()
  local x, y = math.cos(time * math.pi) * 64, math.sin(time * math.pi) * 64
  local w, h = kot.width * 2, kot.height * 2

  clear(black)

  push()
  translate(width / 2, height / 2)
  translate(-w / 2, -h / 2)
  blit(
    kot,
    x, y, w, h,
    10, 10,
    1 + (math.cos(time * math.pi) + 1) / 2 * kot.width,
    1 + (math.sin(time * math.pi) + 1) / 2 * kot.height,
    pattern(kot):filter(Linear):extend(Repeat)
  )
  pop()
end
