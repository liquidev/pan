animation { width = 400, height = 400, length = 4.0, framerate = 25 }

sans = font("sans-serif")

background = solid(hex"#20d4ac")
white = solid(gray(255))

Size = 128

function render()
  clear(background)

  push()

  translate(width / 2, height / 2)
  translate(keyframes {
    { time = 0.0, val = -width / 2 - Size / 2 },
    { time = 1.0, val = 0,                    easing = quinticOut },
    { time = 2.0, val = width / 2 + Size / 2, easing = quinticIn },
  }, 0)
  rotate(ease(0, math.pi, 0.0, 1.5, quinticInOut))

  rectf(-Size / 2, -Size / 2, Size, Size, white)

  pop()
end
