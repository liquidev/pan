import std/options
import std/os
import std/parseopt
import std/streams
import std/strutils

import cairo
import nimLUA
import rapid/gfx
import rapid/gfx/text
import rapid/res/images
import rapid/res/textures
import rdgui/control
import rdgui/windows

import imageview
import res


# types

type
  Mode = enum
    modePreview = "preview"
    modeRender = "render"

  Color = object
    r, g, b, a: float
  PaintKind = enum
    pkSolid
    pkPattern
  PanLineCap = enum
    lcButt
    lcSquare
    lcRound
  PanLineJoin = enum
    ljMiter
    ljBevel
    ljRound
  Paint = ref object
    case kind: PaintKind
    of pkSolid:
      color: Color
    of pkPattern:
      patt: ptr Pattern
    lineWidth: float
    lineCap: LineCap
    lineJoin: LineJoin
  PanFontSlant = enum
    fsNone
    fsItalic
    fsOblique
  PanFontWeight = enum
    fwNormal
    fwBold
  Font = ref object
    name: string
    slant: FontSlant
    weight: FontWeight


# cli

const Help = slurp("help.txt")

var
  luafile = ""
  mode = modePreview

for kind, key, val in getopt(commandLineParams()):
  if kind == cmdArgument:
    if luafile.len == 0: luafile = key
    else: mode = parseEnum[Mode](key)

if luafile.len == 0:
  quit(Help, QuitSuccess)


# the animation

var
  framerate = 60.0
  length: float
  currentTime = 0.0
  playing = false
  errors = ""

proc error(msg: string) =
  echo msg
  errors.add(msg & '\n')


# api

var
  lua = newNimLua()
  cairoSurface: ptr Surface
  cairoCtx: ptr Context

lua.openlibs()


# running

proc getError(lua: PState): string =
  let error = lua.toString(-1)
  lua.pop(1)
  result = error

proc pcallErrorHandler(lua: PState): cint {.cdecl.} =
  let error = lua.toString(-1)
  lua.pop(1)
  lua.traceback(lua, error, 1)
  result = 1

lua.pushcfunction(pcallErrorHandler)
let pcallErrorHandlerIndex = lua.gettop()

type
  StringReaderState = object
    str: cstring
    sentToLua: bool
  FileReaderState = object
    stream: FileStream
    buffer: array[1024, char]

proc stringReader(lua: PState, data: pointer,
                  size: var csize_t): cstring {.cdecl.} =
  var state = cast[ptr StringReaderState](data)
  if not state.sentToLua:
    size = state.str.len.csize_t
    result = cast[cstring](state.str[0].unsafeAddr)
    state.sentToLua = true
  else:
    size = 0
    result = nil

proc fileReader(lua: PState, data: pointer,
                size: var csize_t): cstring {.cdecl.} =
  var state = cast[ptr FileReaderState](data)
  if state.stream.atEnd:
    size = 0
    return nil
  size = state.stream.readData(addr state.buffer, sizeof(state.buffer)).csize_t
  result = addr state.buffer

proc loadFile(lua: PState, filename: string): Option[string] =
  var state = FileReaderState(stream: openFileStream(filename, fmRead))
  if lua.load(fileReader, addr state, '@' & filename, "bt") != LUA_OK:
    result = some(lua.getError())

proc loadString(lua: PState, filename, str: string): Option[string] =
  var state: StringReaderState
  state.str = cast[cstring](alloc((str.len + 1) * sizeof(char)))
  copyMem(state.str, str[0].unsafeAddr, (str.len + 1) * sizeof(char))
  if lua.load(stringReader, addr state, filename, "bt") != LUA_OK:
    result = some(lua.getError())
  dealloc(state.str)

proc call(lua: PState, argCount, resultCount: int): Option[string] =
  if lua.pcall(argCount.cint, resultCount.cint,
               pcallErrorHandlerIndex) != LUA_OK:
    result = some(lua.getError())

proc runFile(lua: PState, filename: string): Option[string] =
  let err = lua.loadFile(filename)
  if err.isSome: return err
  result = lua.call(0, 0)

proc runString(lua: PState, filename, str: string): Option[string] =
  let err = lua.loadString(filename, str)
  if err.isSome: return err
  result = lua.call(0, 0)

# proc implementations
# most procs are prefixed with 'pan' because nimLUA doesn't like overloads. gaah

# -- CANVAS

proc panAnimation(width, height: int, alength, aframerate: float) =
  if cairoSurface != nil:
    cairoSurface.destroy()
  if cairoCtx != nil:
    cairoCtx.destroy()
  cairoSurface = cairo.imageSurfaceCreate(FormatArgb32, width.cint, height.cint)
  cairoCtx = cairo.create(cairoSurface)
  length = alength
  framerate = aframerate
  lua.pushnumber(width.float64)
  lua.pushnumber(height.float64)
  lua.pushnumber(length)
  lua.pushnumber(framerate)
  lua.setglobal("framerate")
  lua.setglobal("length")
  lua.setglobal("height")
  lua.setglobal("width")

# -- COLOR

proc newColor(r, g, b, a: float): Color =
  Color(r: r / 255, g: g / 255, b: b / 255, a: a / 255)

# -- PAINTS

proc toCairo(lineCap: PanLineCap): LineCap =
  case lineCap
  of lcButt: LineCapButt
  of lcSquare: LineCapSquare
  of lcRound: LineCapRound

proc toCairo(lineJoin: PanLineJoin): LineJoin =
  case lineJoin
  of ljMiter: LineJoinMiter
  of ljBevel: LineJoinBevel
  of ljRound: LineJoinRound

proc solidPaint(col: Color): Paint =
  Paint(kind: pkSolid, color: col,
        lineWidth: 1.0,
        lineCap: LineCapButt,
        lineJoin: LineJoinMiter)

proc destroyPaint(paint: Paint) =
  if paint.kind == pkPattern:
    paint.patt.destroy()

proc setLineWidth(paint: Paint, width: float): Paint =
  paint.lineWidth = width
  result = paint

proc setLineCap(paint: Paint, cap: PanLineCap): Paint =
  paint.lineCap = cap.toCairo
  result = paint

proc setLineJoin(paint: Paint, join: PanLineJoin): Paint =
  paint.lineJoin = join.toCairo
  result = paint

proc use(paint: Paint) =
  if paint.kind == pkSolid:
    cairoCtx.setSourceRgba(paint.color.r,
                           paint.color.g,
                           paint.color.b,
                           paint.color.a)
  else:
    cairoCtx.setSource(paint.patt)
  cairoCtx.setLineWidth(paint.lineWidth)
  cairoCtx.setLineCap(paint.lineCap)
  cairoCtx.setLineJoin(paint.lineJoin)

# -- DRAWING

proc panClear(paint: Paint) =
  paint.use()
  cairoCtx.paint()

proc panPush() =
  cairoCtx.save()

proc panPop() =
  cairoCtx.restore()

proc panBegin() =
  cairoCtx.newPath()

proc panMoveTo(x, y: float) =
  cairoCtx.moveTo(x, y)

proc panLineTo(x, y: float) =
  cairoCtx.lineTo(x, y)

proc panRect(x, y, w, h: float) =
  cairoCtx.rectangle(x, y, w, h)

proc panArc(x, y, r, astart, aend: float) =
  cairoCtx.arc(x, y, r, astart, aend)

proc panClose() =
  cairoCtx.closePath()

proc panFill(paint: Paint) =
  paint.use()
  cairoCtx.fillPreserve()

proc panStroke(paint: Paint) =
  paint.use()
  cairoCtx.strokePreserve()

proc panClip() =
  cairoCtx.clipPreserve()

proc toCairo(slant: PanFontSlant): FontSlant =
  case slant
  of fsNone: FontSlantNormal
  of fsItalic: FontSlantItalic
  of fsOblique: FontSlantOblique

proc toCairo(weight: PanFontWeight): FontWeight =
  case weight
  of fwNormal: FontWeightNormal
  of fwBold: FontWeightBold

proc newFont(name: string, weight: PanFontWeight,
             slant: PanFontSlant): Font =
  Font(name: name, slant: slant.toCairo, weight: weight.toCairo)

proc use(font: Font) =
  cairoCtx.selectFontFace(font.name, font.slant, font.weight)

proc panTextSize(font: Font, text: string, size: float, w, h: var float) =
  var
    fextents: FontExtents
    textents: TextExtents
  font.use()
  cairoCtx.setFontSize(size)
  cairoCtx.fontExtents(addr fextents)
  cairoCtx.textExtents(text, addr textents)
  w = textents.width + textents.x_bearing
  h = fextents.ascent

proc panText(font: Font, x, y: float, text: string, size: float,
             w, h: float, halign: RTextHAlign, valign: RTextVAlign) =
  var tw, th: float
  panTextSize(font, text, size, tw, th)
  let
    tx =
      case halign
      of taLeft: x
      of taCenter: x + w / 2 - tw / 2
      of taRight: x + w - tw
    ty =
      case valign
      of taTop: y + th
      of taMiddle: y + h / 2 + th / 2
      of taBottom: y + h
  cairoCtx.moveTo(tx, ty)
  cairoCtx.textPath(text)

proc panTranslate(x, y: float) =
  cairoCtx.translate(x, y)

proc panScale(x, y: float) =
  cairoCtx.scale(x, y)

proc panRotate(z: float) =
  cairoCtx.rotate(z)

# bindings

lua.bindEnum:
  PanLineCap -> GLOBAL
  PanLineJoin -> GLOBAL
  PanFontWeight -> GLOBAL
  PanFontSlant -> GLOBAL
  RTextHAlign -> GLOBAL
  RTextVAlign -> GLOBAL

lua.bindObject(Color):
  newColor -> "_createRgbaImpl"  # defer for gray(), rgb(), rgba()
  r(get, set)
  g(get, set)
  b(get, set)
  a(get, set)

lua.bindObject(Paint):
  solidPaint -> "_createSolidImpl"  # defer for solid()
  setLineWidth -> "lineWidth"
  setLineCap -> "lineCap"
  setLineJoin -> "lineJoin"
  ~destroyPaint

lua.bindObject(Font):
  newFont -> "_createImpl"  # defer for font()

lua.bindProc:
  # -- CANVAS
  panAnimation -> "pan__animationImpl"
  # -- DRAWING
  panClear -> "clear"
  panPush -> "push"
  panPop -> "pop"
  panBegin -> "begin"
  panMoveTo -> "moveTo"
  panLineTo -> "lineTo"
  panRect -> "rect"
  panArc -> "arc"
  panClose -> "close"
  panFill -> "fill"
  panStroke -> "stroke"
  panClip -> "clip"
  panText -> "pan__textImpl"  # defer for default parameters
  panTextSize -> "textSize"
  # -- TRANSFORMS
  panTranslate -> "translate"
  panScale -> "scale"
  panRotate -> "rotate"

block loadLuapan:
  const luapan = slurp("pan.lua")
  let error = lua.runString("luapan", luapan)
  if error.isSome:
    quit("error in luapan:\n" & error.get & "\nplease report this", -1)

proc reload() =
  errors = ""
  let error = lua.runFile(luafile)
  if error.isSome:
    error("error in luafile:\n" & error.get)
reload()

proc renderFrame(): Option[string] =
  lua.pushnumber(currentTime)
  lua.setglobal("time")

  lua.getglobal("render")
  if not lua.isfunction(-1):
    error("error in luafile: no render() function")
  result = lua.call(0, 0)

  lua.pushnil()
  lua.setglobal("time")

proc updateWithFrame(tex: RTexture) =
  if cairoSurface != nil:
    var
      width = cairoSurface.getWidth()
      height = cairoSurface.getHeight()
      surfaceData = cairoSurface.getData()
      stride = cairoSurface.getStride()
      dataString = ""
    for y in 0..<height:
      for x in 0..<width:
        let
          index = x * sizeof(uint32) + y * stride
          colorPtr = cast[ptr uint32](surfaceData[index].unsafeAddr)
          color = colorPtr[]
          alpha = cast[char](uint8(color shr 24))
          red = cast[char](uint8((color shr 16) and 0xff))
          green = cast[char](uint8((color shr 8) and 0xff))
          blue = cast[char](uint8(color and 0xff))
        dataString.add(red)
        dataString.add(green)
        dataString.add(blue)
        dataString.add(alpha)
    let image = newRImage(width, height, dataString)
    tex.update(image)

proc preview() =
  const
    BackgroundPng = slurp("background.png")
    OpenSansTtf = slurp("OpenSans-Regular.ttf")

    Tc = (minFilter: fltLinear, magFilter: fltNearest,
          wrapH: wrapClampToEdge, wrapV: wrapClampToEdge)

  var
    win = initRWindow()
      .size(1280, 720)
      .title("pan – " & luafile)
      .open()
    surface = win.openGfx()

    bgTexture = newRTexture(readRImagePng(BackgroundPng))
    frameTexture =
      if cairoSurface != nil:
        newRTexture(cairoSurface.getWidth(), cairoSurface.getHeight(), Tc)
      else:
        newRTexture(1, 1, Tc)  # fallback if the cairo surface wasn't
                               # initialized properly
    wm = newWindowManager(win)
    root = wm.newWindow(0, 0, 0, 0)

    reloadPollTimer = 0.0
    lastLuafileMod = getLastModificationTime(luafile)

  sans = newRFont(OpenSansTtf, 13)
  sans.tabWidth = 24

  wm.add(root)
  var
    frameView = newImageView(0, 0, 0, 0, frameTexture)
  root.add(frameView)

  proc layout() =
    frameView.width = surface.width
    frameView.height = surface.height
  layout()

  win.onResize do (width, height: Natural):
    layout()

  proc onKey(key: Key, scancode: int, mods: RModKeys) =
    case key
    of keyQ:
      quitGfx()
      quit()
    of keyR:
      reload()
    of keySpace:
      playing = not playing
    of keyLeft:
      currentTime -= 1 / framerate
    of keyRight:
      currentTime += 1 / framerate
    of keyBackspace:
      currentTime = 0
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

      if playing:
        currentTime += deltaTime
        if currentTime > length:
          currentTime = 0

      reloadPollTimer += deltaTime
      if reloadPollTimer > 0.25:
        if getLastModificationTime(luafile) != lastLuafileMod:
          reload()
          lastLuafileMod = getLastModificationTime(luafile)
        reloadPollTimer = 0

      block transparencyGrid:
        ctx.begin()
        ctx.texture = bgTexture
        ctx.rect(0, 0, surface.width, surface.height,
                 (0.0, 0.0, surface.width / 32, surface.height / 32))
        ctx.draw()
        ctx.noTexture()

      if errors.len == 0:
        let renderError = renderFrame()
        if renderError.isSome:
          error(renderError.get)

      frameTexture.updateWithFrame()

      wm.draw(ctx, step)

      ctx.text(sans, 8, 8, "time: " &
               formatFloat(currentTime, precision = 3) & " / " & $length,
               surface.width - 16, surface.height - 16, taLeft, taBottom)

      block showErrors:
        if errors.len > 0:
          var i = 0
          for line in errors.splitLines:
            let ln =
              if i < 10: line
              elif i == 10: "…"
              else: ""
            if i > 10: break
            ctx.color = gray(0)
            ctx.text(sans, 9, 9 + i.float * 16, ln)
            ctx.color = rgb(252, 85, 88)
            ctx.text(sans, 8, 8 + i.float * 16, ln)
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
    frameTime = 1 / framerate
    frameCount = ceil(length / frameTime).int
  log "total ", frameCount, " frames"

  for i in 1..frameCount:
    let
      filename = addFileExt(outdir / $i, "png")
      percentage = i / frameCount * 100
    let error = renderFrame()
    if error.isSome:
      stderr.write('\n')
      stderr.writeLine(error.get)
      quit(1)
    let status = cairoSurface.writeToPng(filename)
    if status != StatusSuccess:
      stderr.writeLine("[in cairo] write to png failed: ", $status)
      quit(-1)
    stderr.write("\rrendering: ", $i, " / ", frameCount,
                 " (", formatFloat(percentage, precision = 3), "%)")
    stderr.flushFile()
    currentTime += frameTime
  stderr.write('\n')

case mode
of modePreview: preview()
of modeRender: renderAll()
