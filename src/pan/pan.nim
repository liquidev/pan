import std/options
import std/os
import std/parseopt
import std/strutils

import cairo
import rapid/gfx
import rapid/gfx/text
import rapid/res/images
import rapid/res/textures
import rdgui/control
import rdgui/windows

from api import Animation, step
import animview
import luaapi
import res
import timeline


# types

type
  Mode = enum
    modePreview = "preview"
    modeRender = "render"


# cli

const Help = slurp("assets/help.txt")

var
  luafile = ""
  mode = modePreview

for kind, key, val in getopt(commandLineParams()):
  if kind == cmdArgument:
    if luafile.len == 0: luafile = key
    else: mode = parseEnum[Mode](key)

if luafile.len == 0:
  quit(Help, QuitSuccess)


# runtime

var se: ScriptEngine

gAnim = new(Animation)
se.init(gAnim, luafile)

proc preview() =
  const
    BackgroundPng = slurp("assets/background.png")
    OpenSansTtf = slurp("assets/fonts/OpenSans-Regular.ttf")
    OpenSansBoldTtf = slurp("assets/fonts/OpenSans-Bold.ttf")

  var
    win = initRWindow()
      .size(1280, 720)
      .title("pan – " & luafile)
      .open()
    surface = win.openGfx()

    bgTexture = newRTexture(readRImagePng(BackgroundPng))
    wm = newWindowManager(win)
    root = wm.newWindow(0, 0, 0, 0)

    reloadPollTimer = 0.0
    lastLuafileMod = getLastModificationTime(luafile)

  gSans = newRFont(OpenSansTtf, 13)
  gSans.tabWidth = 24
  gSansBold = newRFont(OpenSansBoldTtf, 13)
  gSansBold.tabWidth = 24

  wm.add(root)
  var
    animView = newAnimationView(0, 0, 0, 0, gAnim)
    timeline = newTimeline(0, 0, 0, gAnim)
  root.add(animView)
  root.add(timeline)

  proc layout() =
    timeline.pos = vec2(0.0, surface.height - timeline.height)
    timeline.width = surface.width
    animView.width = surface.width
    animView.height = surface.height - timeline.height

  layout()

  win.onResize do (width, height: Natural):
    layout()

  proc onKey(key: Key, scancode: int, mods: RModKeys) =
    case key
    of keyQ:
      quitGfx()
      quit()
    of keyR:
      se.reload()
    else: discard

  win.onKeyPress(onKey)
  win.onKeyRepeat(onKey)

  var lastTime = time()
  surface.loop:
    draw ctx, step:
      let
        now = time()
        deltaTime = now - lastTime
      lastTime = now

      timeline.playback.tick(deltaTime)

      reloadPollTimer += deltaTime
      if reloadPollTimer > 0.25:
        if getLastModificationTime(luafile) != lastLuafileMod:
          se.reload()
          lastLuafileMod = getLastModificationTime(luafile)
        reloadPollTimer = 0

      block transparencyGrid:
        ctx.begin()
        ctx.texture = bgTexture
        ctx.rect(0, 0, surface.width, surface.height,
                 (0.0, 0.0, surface.width / 32, surface.height / 32))
        ctx.draw()
        ctx.noTexture()

      if se.errors.isNone:
        se.renderFrame()

      wm.draw(ctx, step)

      block showErrors:
        if se.errors.isSome:
          let errors = se.errors.get
          var i = 0
          for line in errors.splitLines:
            let ln =
              if i < 10: line
              elif i == 10: "…"
              else: ""
            if i > 10: break
            ctx.color = gray(0)
            ctx.text(gSans, 9, 9 + i.float * 16, ln)
            ctx.color = rgb(252, 85, 88)
            ctx.text(gSans, 8, 8 + i.float * 16, ln)
            inc(i)
          ctx.color = gray(255)
    update:
      discard

proc renderAll() =

  proc log(x: varargs[string, `$`]) =
    stderr.writeLine(x.join())
    stderr.flushFile()

  let
    (path, name, _) = luafile.splitFile
    outdir = path/name
  log "rendering to ", outdir/"#.png"
  if not (dirExists(outdir) or fileExists(outdir)):
    createDir(outdir)
  else:
    quit("error: " & outdir & " exists. quitting", -1)

  let
    frameTime = 1 / gAnim.framerate
    frameCount = ceil(gAnim.length / frameTime).int
  log "total ", frameCount, " frames"

  for i in 1..frameCount:
    let
      filename = addFileExt(outdir / $i, "png")
      percentage = i / frameCount * 100
    se.renderFrame()
    if se.errors.isSome:
      stderr.write('\n')
      stderr.writeLine(se.errors.get)
      quit(1)
    let status = gAnim.surface.writeToPng(filename)
    if status != StatusSuccess:
      log "[in cairo] write to png failed: ", status
      quit(-1)
    stderr.write("\rrendering: ", $i, " / ", frameCount,
                 " (", formatFloat(percentage, precision = 3), "%)")
    stderr.flushFile()
    gAnim.step(frameTime)
  stderr.write('\n')

case mode
of modePreview: preview()
of modeRender: renderAll()
