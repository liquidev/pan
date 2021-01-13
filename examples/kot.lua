animation { width = 300, height = 300, length = 1, framerate = 1 }

local black = solid(hex"#000000")
local kot = image.load("kot.png")

function render()
  local w, h = kot.width * 2, kot.height * 2

  clear(black)

  push()
  translate(width / 2, height / 2)
  translate(-w / 2, -h / 2)
  blit(kot, 0, 0, w, h, { filter = Linear })
  pop()
end
