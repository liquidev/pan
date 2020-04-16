animation { width = 400, height = 400, length = 4.0, framerate = 25 }

sans = font("sans-serif")

background = solid(hex"#20d4ac")
white = solid(gray(255))

Size = 128

function render()
  clear(background)
  
  push()

  translate(width / 2, height / 2)
  translate(ease(-width / 2 - Size, 0, 0, 2, quinticOut), 0)
  translate(ease(0, width / 2 + Size, 1, 3, quinticIn), 0)
  rotate(ease(0, math.pi, 0.5, 2, quinticInOut))

  rectf(-Size / 2, -Size / 2, Size, Size, white)
  
  pop()
end
