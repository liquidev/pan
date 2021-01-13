animation { width = 400, height = 400, length = 1, framerate = 1 }

local canvas = image.empty(100, 100)

local black = solid(hex"#000000")
local white = solid(hex"#ffffff"):antialiasing(aaNone)

function render()

  local output = switch(canvas)
  clear(black)
  circles(width / 2, height / 2, 32, white)

  switch(output)
  blit(canvas, 0, 0, width, height)

end
