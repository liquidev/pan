animation { width = 400, height = 400, length = 2.0, framerate = 30 }

background = solid(hex"#1F2430")
foreground = solid(hex"#CBCCC6"):lineWidth(2)

function grid(w, h, sx, sy, nx, ny, starttime, len)
  local x = -(nx - 1) / 2 * sx
  for i = 1, nx do
    local h = easel(0, h, starttime + (i - 1) / 10, len, quarticOut)
    moveTo(x, -h / 2)
    lineTo(x, h / 2)
    x = x + sx
  end

  local y = -(ny - 1) / 2 * sy
  for i = 1, ny do
    local w = easel(0, w, starttime + (i - 1) / 10, len, quarticOut)
    moveTo(-w / 2, y)
    lineTo(w / 2, y)
    y = y + sy
  end
end

function render()
  clear(background)

  begin()
  push()
  local globalsc = ease(1, 4, 0.5, 2, quinticInOut)
  scale(globalsc, globalsc)

  push()
  translate(width / 2, height / 2)
  grid(width, height, width / 4, height / 4, 3, 3, -10, 0)
  pop()

  push()
  translate(width / 8, height / 8)
  scale(1/4, 1/4)
  grid(width, height, width / 4, height / 4, 3, 3, 0, 1)
  pop()
  
  pop()

  stroke(foreground)
end
