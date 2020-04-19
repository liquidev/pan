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
Apart from that, its API is simple to learn and use. You don't even have to go
online for a reference: it's built in to the program, right after the help text.
Simply run `pan | less` and read away!

## Installation

```
git clone https://github.com/liquid600pgm/pan
cd pan
nimble install
```

## Usage

```bash
# display help text + API reference:
pan | less

# show preview window:
pan file.lua
# the above is a shorthand for:
pan file.lua preview

# render your animation to a directory next to the luafile:
pan file.lua render
```

### Preview controls

- Middle mouse button – pan view
- Scroll wheel – zoom in/out
- Right mouse button – reset scroll and zoom
- <kbd>Space</kbd> – play/pause
- <kbd>←</kbd>, <kbd>→</kbd> – step one frame backwards/forwards
- <kbd>← Backspace</kbd> – return to beginning of animation

## Example

Here's an example of a short luafile you can preview with `pan <file>`:
```lua
animation { width = 400, height = 400, length = 3.0, framerate = 25 }

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
```

![hello.lua rendered at 25 fps](hello.webp)

You can find more examples in the `examples/` directory.
