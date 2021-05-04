# pan - puny animator

pan is an program that allows for easily creating animations using Lua.
It is primarily geared towards 2D motion graphics.

The commonly used motion graphics software out there sucks. Adobe After Effects
is slow and bulky, and Blender isn't geared very well for motion graphics. Both
need plugins to make creating nice, satisfying, sequential animations fast and
efficient. Why do we have to stick with software that clearly isn't made for
this purpose, when we can create better alternatives?

pan is the answer to this: using a simple, but powerful API, embracing the
simplicity of Lua as a scripting language, and providing hot reloading to make
small edits fast and easy to do, it makes the creation of 2D motion graphics a
breeze. Its render times are really fast, and the preview can run your animation
in full 60 fps—even when your animation is to be exported in a lower framerate.
The preview is capable of running even on low-end hardware, thanks to OpenGL
hardware acceleration.
Apart from that, pan's API is simple to learn and use. You don't even have to go
online for a reference: it's built in to the program, right after the help text.
Simply run `pan r` and read away!

## Installation

```
nimble install https://github.com/liquidev/pan
```

## Usage

```bash
# display help text:
pan
# display API reference:
pan r
# look up reference for rect:
pan r rect

# show preview window:
pan file.lua
# the above is a shorthand for:
pan file.lua preview

# render your animation to a directory next to the luafile:
pan file.lua render
# maybe to a gif, animated webp, or video file (FFmpeg required):
pan file.lua render -x:gif
pan file.lua render -x:webp
pan file.lua render -x:webmVP9
```

### Preview controls

- Middle mouse button – pan view
- Scroll wheel – zoom in/out
- Right mouse button – reset zoom
- <kbd>Q</kbd> – quit preview
- <kbd>R</kbd> – reload animation
- <kbd>Space</kbd> – play/pause
- <kbd>←</kbd> – previous frame
- <kbd>→</kbd> – next frame
- <kbd>Shift</kbd> <kbd>←</kbd> – 0.25s back
- <kbd>Shift</kbd> <kbd>→</kbd> – 0.25s forward
- <kbd>Ctrl</kbd> <kbd>←</kbd> – jump to start of animation
- <kbd>Ctrl</kbd> <kbd>→</kbd> – jump to end of animation

## Example

Here's an example of a short luafile you can preview with `pan <file>`:
```lua
animation { width = 400, height = 400, length = 3.0, framerate = 25 }

local background = solid(hex"#20d4ac")
local white = solid(gray(255))

local size = 128

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

  rectf(-size / 2, -size / 2, size, size, white)

  pop()
end
```

![hello.lua rendered at 25 fps](hello.webp)

You can find more examples in the `examples/` directory.
