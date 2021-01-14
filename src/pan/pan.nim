import std/monotimes
import std/options
import std/os
import std/osproc
import std/parseopt
import std/strutils
import std/tables
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
import stb_image/write as stbiw
import weave

from api import Animation, step
import animview
import help
import luaapi
import res
import timeline


# types

type
  Mode = enum
    modePreview = "preview"
    modeRender = "render"
    modeReference = " unreachable"
                    # ↑ because parseopt strips whitespace off of values


# cli

var
  luafile = ""
  mode = modePreview
  referenceQueries: seq[string]

  # render options
  renderClean = false
  framerateOverride = 0.0
  ffmpegExport = false
  ffmpegArgs: seq[string]

const exportArgs = {
  "webmvp9": @["-c:v", "libvpx-vp9", "-b:v", "1M", "@@.webm"],
  "webp": @["-lossless", "1", "-loop", "0", "@@.webp"],
  "gif": @[
    # https://superuser.com/questions/556029/how-do-i-convert-a-video-to-gif-using-ffmpeg-with-reasonable-quality
    "-vf", "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",
    "-loop", "0",
    "@@.gif"
  ]
}.toTable

var argIndex = 0
for kind, key, value in getopt(commandLineParams()):

  case kind
  of cmdArgument:
    if luafile.len == 0 and mode != modeReference:
      if key in ["r", "reference"]: mode = modeReference
      else: luafile = key
    else:
      if mode == modeReference: referenceQueries.add(key)
      else: mode = parseEnum[Mode](key)

  of cmdShortOption, cmdLongOption:

    case mode
    of modePreview: quit "preview mode does not accept any options", 1

    of modeRender:
      case key
      of "c", "clean": renderClean = true
      of "f", "framerate": framerateOverride = parseFloat(value)
      of "x", "export":
        ffmpegExport = true
        if value.normalize notin exportArgs:
          quit "unsupported export format: " & value, 1
        ffmpegArgs = exportArgs[value.normalize]
      of "ffmpeg":
        ffmpegExport = true
        var args = commandLineParams()[argIndex + 1 .. ^1]
        if ffmpegArgs.len == 0:
          ffmpegArgs = move args
        else:
          let
            head = ffmpegArgs[1..^2]
            tail = ffmpegArgs[^1]
          reset ffmpegArgs
          ffmpegArgs.add(head)
          ffmpegArgs.add(args)
          ffmpegArgs.add(tail)
        break
      else: quit "unknown render option: " & key, 1

    of modeReference:
      case key
      of "p", "pager": gHelpPager = value
      of "P", "passPager": gHelpPagerArgs = value
      else: quit "unknown reference option: " & key, 1

  of cmdEnd: doAssert false

  inc argIndex

if mode == modeReference:
  if referenceQueries.len == 0:
    printReference()
  else:
    if not stdout.queryReference(referenceQueries):
      quit 1
  quit 0
elif luafile.len == 0:
  printHelp()
  quit 0


# runtime

var se: ScriptEngine

gAnim = new(Animation)
se.init(gAnim, luafile)

proc preview() =

  const
    BackgroundPng = slurp("assets/background.png")
    OpenSansTtf = slurp("assets/fonts/OpenSans-Regular.ttf")
    SourceCodeProTtf = slurp("assets/fonts/SourceCodePro-Medium.ttf")

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
  gMono = graphics.newFont(SourceCodeProTtf, 13)

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

    ui.keyPressed keyQ:
      quit 0

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

  proc writePngJob(filename: string, width, height: int,
                   cdata: pointer): bool {.nimcall, thread.} =
    var data = cast[ptr UncheckedArray[uint8]](cdata)

    # shuffle ARGB → RGBA around
    {.push checks: off, stacktrace: off.}
    for y in 0..<height:
      for x in 0..<width:
        let
          a = 4 * (x + y * width)
          r = a + 1
          g = r + 1
          b = g + 1
        (data[a], data[r], data[g], data[b]) =
          when cpuEndian == bigEndian: (data[r], data[g], data[b], data[a])
          else: (data[a], data[b], data[g], data[r])
    {.pop.}

    # save it
    result = stbiw.writePng(filename, width, height, comp = 4,
                            data.toOpenArray(0, 4 * width * height))

    deallocShared(cdata)

  let
    (path, name, _) = luafile.splitFile
    outdir = path/name
  log "rendering to ", outdir/"#.png"

  if renderClean and dirExists(outdir):
    log "removing existing output directory"
    removeDir(outdir)

  if not (dirExists(outdir) or fileExists(outdir)):
    createDir(outdir)
  else:
    quit("error: " & outdir & " exists. quitting", -1)

  se.reload()

  let
    framerate =
      if framerateOverride > 0:
        log "overriding framerate to ", framerateOverride, " fps"
        framerateOverride
      else:
        gAnim.framerate
    frameTime = 1 / framerate
    frameCount = ceil(gAnim.length / frameTime).int
  log "total ", frameCount, " frames"

  init Weave

  var jobs: seq[FlowVar[bool]]
  let
    (width, height) = (gAnim.surface.getWidth, gAnim.surface.getHeight)
    frameSize = 4 * width * height
  for i in 1..frameCount:
    let
      filename = addFileExt(outdir / $i, "png")
      percentage = i / frameCount * 100

    se.renderFrame()
    if se.errors.isSome:
      stderr.write('\n')
      stderr.writeLine(se.errors.get)
      quit(1)

    var data = allocShared(frameSize)
    copyMem(data, gAnim.surface.getData, frameSize)
    jobs.add(spawn writePngJob(filename, width, height, data))

    gAnim.step(frameTime)

    stderr.write("\rrendering: ", i, " / ", frameCount,
                 " (", formatFloat(percentage, precision = 3), "%)")
    stderr.flushFile()

    Weave.loadBalance()
  stderr.write('\n')

  log "awaiting PNG write jobs"
  var finishedCount = 0
  while finishedCount < frameCount:
    for fv in jobs.mitems:
      if fv.isReady:
        assert sync(fv), "writing PNG for frame " & $finishedCount & " failed"
        inc finishedCount
    sleep(100)

    let percentage = finishedCount / frameCount * 100
    stderr.write("\rprogress: ", finishedCount, " / ", frameCount,
                 " (", formatFloat(percentage, precision = 3), "%)")
    stderr.flushFile()

    Weave.loadBalance()

  stderr.write('\n')

  exit Weave

  if ffmpegExport:
    log "exporting animation with FFmpeg"

    var params = @["-hide_banner", "-r", $int(framerate), "-i", outdir/"%d.png"]
    params.add(ffmpegArgs)
    for param in params.mitems:
      param = param.replace("@@", outdir)

    log "FFmpeg parameters:"
    log params.join(" ").indent(2)

    log "starting FFmpeg"
    let
      ffmpegExec = findExe("ffmpeg")
      ffmpeg = startProcess(
        ffmpegExec,
        args = params,
        options = {poParentStreams},
      )
      errorCode = waitForExit(ffmpeg)

    if errorCode == 0:
      log "FFmpeg exited successfully"
    else:
      log "FFmpeg failed with error code: ", errorCode

    close ffmpeg

case mode
of modePreview: preview()
of modeRender: renderAll()
else: assert false, "unreachable"
