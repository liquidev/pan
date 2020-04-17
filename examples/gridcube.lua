-- this example renders a pseudo-3D cube using some basic matrix math.

animation { width = 400, height = 400, length = 6, framerate = 25 }

Palette = {
  hex"#081944",
  hex"#28286A",
  hex"#4E3690",
  hex"#7B40B6",
  hex"#AE46D9",
  hex"#E745F8",
}

Background = solid(Palette[1])

CubeSidePaints = {
  solid(Palette[4]),
  solid(Palette[5]),
  solid(Palette[6]),
}

GridLinePaints = {
  solid(Palette[2]):lineWidth(4):lineCap(lcRound),
  solid(Palette[3]):lineWidth(4):lineCap(lcRound),
  solid(Palette[4]):lineWidth(4):lineCap(lcRound),
}

GridLineLengths = {
  1.0, 0.8, 0.6
}

function grid(w, h, sx, sy, nx, ny, starttime, endtime)
  -- Draws and animates a grid with nx, ny lines.

  local function gradientline(x0, y0, x1, y1)
    local mx = (x0 + x1) / 2
    local my = (y0 + y1) / 2
    local ex0 =
      easel(easel(mx, x0, starttime, 2, quinticOut), mx, endtime, 2, quinticIn)
    local ex1 =
      easel(easel(mx, x1, starttime, 2, quinticOut), mx, endtime, 2, quinticIn)
    local ey0 =
      easel(easel(my, y0, starttime, 2, quinticOut), my, endtime, 2, quinticIn)
    local ey1 =
      easel(easel(my, y1, starttime, 2, quinticOut), my, endtime, 2, quinticIn)
    if time > starttime and time < endtime + 2 then
      for i, t in ipairs(GridLineLengths) do
        local tx0 = interp(ex0, ex1, t)
        local tx1 = interp(ex1, ex0, t)
        local ty0 = interp(ey0, ey1, t)
        local ty1 = interp(ey1, ey0, t)
        line(tx0, ty0, tx1, ty1, GridLinePaints[i])
      end
    end
  end

  local x = -(nx - 1) / 2 * sx
  for i = 1, nx do
    gradientline(x, -h / 2, x, h / 2)
    x = x + sx
  end
  local y = -(ny - 1) / 2 * sy
  for i = 1, ny do
    gradientline(-w / 2, y, w / 2, y)
    y = y + sy
  end
end

function cube(xy, z)
  if z > 0 then
    begin()
    moveTo(-xy, xy)
    lineTo(xy, xy)
    lineTo(xy - z, xy - z)
    lineTo(-xy - z, xy - z)
    close()
    fill(CubeSidePaints[1])

    begin()
    moveTo(xy, xy)
    lineTo(xy, -xy)
    lineTo(xy - z, -xy - z)
    lineTo(xy - z, xy - z)
    close()
    fill(CubeSidePaints[2])

    begin()
    rect(-xy - z, -xy - z, xy * 2, xy * 2)
    fill(CubeSidePaints[3])
  end
end

orthoStart = 0.2
orthoLen = 2.0
cubeStart = 2.0
cubeTransition = 0.2
cubeLen = 1.5
cubeEnd = length - cubeLen - cubeTransition
cubeSize = 60
cubeHeight = 110

function wipe(x, y, w, h, starttime, len, mode)
  if (mode == "in" and time < starttime + len) or
     (mode == "out" and time > starttime) then
    if mode == "in" then
      w = easel(0, w, starttime, len, linear)
      h = easel(0, h, starttime, len, linear)
    elseif mode == "out" then
      w = easel(w, 0, starttime, len, linear)
      h = easel(h, 0, starttime, len, linear)
    end
    begin()
    rect(x, y, w, h)
    clip()
  end
end

function render()
  clear(Background)

  push()

  translate(width / 2, height / 2)
  translate(0, easel(0, 50, orthoStart, orthoLen, quinticInOut))
  scale(1, easel(1, 2/3, orthoStart, orthoLen, quinticInOut))
  rotate(easel(0, math.pi / 4, orthoStart, orthoLen, quinticInOut))

  grid(300, 300, 120, 120, 2, 2, 0, 2)

  push(-cubeSize)
  wipe(-cubeSize, -cubeSize, cubeSize * 2, cubeSize * 2,
       cubeStart, cubeTransition, "in")
  wipe(-cubeSize, -cubeSize, cubeSize * 2, cubeSize * 2,
       cubeEnd + cubeLen, cubeTransition, "out")
  cube(cubeSize, keyframes{
    { time = cubeStart, val = 0 },
    { time = cubeStart + cubeTransition, val = 0.0001 },
    { time = cubeTransition + cubeStart + cubeLen, val = cubeHeight,
      easing = quinticOut },
    { time = cubeEnd, val = cubeHeight },
    { time = cubeEnd + cubeLen, val = 0.0001, easing = quinticIn },
  })
  pop()

  pop()
end
