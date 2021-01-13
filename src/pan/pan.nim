import std/monotimes
import std/options
import std/os
import std/parseopt
import std/strutils
import std/times

import aglet
import aglet/window/glfw
import cairo
import rapid/graphics
import rapid/graphics/image
import rapid/graphics/meshes
import rapid/graphics/programs
import rapid/graphics/vertex_types
import rapid/ui

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

  var aglet = initAglet()
  aglet.initWindow()

  var
    window = aglet.newWindowGlfw(960, 540, "pan · " & luafile,
                                 winHints(resizable = true))
    graphics = window.newGraphics()

    directTextured = window.programDirect(Vertex2dUv)
    dpDefault = defaultDrawParams()

    background = window.newTexture2D(Rgba8, readPngImage(BackgroundPng))
    backgroundRect = window.newMesh[:Vertex2dUv](muStream, dpTriangles)

    ui = block:
      var r = new PanUi
      r.init(window, graphics)
      r
    animationView = ui.initAnimationView(gAnim)
    timeline = ui.initTimeline(gAnim)

    reloadPollTimer: float32 = 0.0
    lastLuafileMod = getLastModificationTime(luafile)

  gSans = graphics.newFont(OpenSansTtf, 13)
  gSans.tabWidth = 24
  gSansBold = graphics.newFont(OpenSansBoldTtf, 13)
  gSansBold.tabWidth = 24

  se.reload()

  var lastTime = getMonoTime()
  while not window.closeRequested:

    window.pollEvents proc (event: InputEvent) =
      ui.processEvent(event)

    let
      now = getMonoTime()
      deltaTime = float32 inNanoseconds(now - lastTime).int / 1_000_000_000
    lastTime = now

    timeline.tick(deltaTime)

    reloadPollTimer += deltaTime
    if reloadPollTimer > 0.25:
      if getLastModificationTime(luafile) != lastLuafileMod:
        se.reload()
        lastLuafileMod = getLastModificationTime(luafile)
      reloadPollTimer = 0

    var frame = window.render()
    frame.clearColor(colBlack)

    backgroundRect.uploadRectangle(
      uv = rectf(vec2f(0), frame.size.vec2f / background.size.vec2f))
    frame.draw(directTextured, backgroundRect, uniforms {
      sampler: background.sampler(minFilter = fmNearest, magFilter = fmNearest),
    }, dpDefault)

    if se.errors.isNone:
      se.renderFrame()

    graphics.resetShape()

    ui.begin(frame)
    ui.font = gSans

    ui.box ui.size, blVertical:
      ui.animationView(animationView, ui.size - vec2f(0, Timeline.height))
      ui.timelineBar(timeline)

    ui.draw(frame)

    graphics.resetShape()

    if se.errors.isSome:
      let errors = se.errors.get
      var i = 0
      for line in errors.splitLines:
        let ln =
          if i < 10: line
          elif i == 10: "…"
          else: ""
        if i > 10: break
        graphics.text(gSans, 9, 9 + i.float32 * 16, ln, color = colBlack)
        graphics.text(gSans, 8, 8 + i.float32 * 16, ln, color = hex"#fc5558")
        inc i

    graphics.draw(frame)

    frame.finish()

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

  se.reload()

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
