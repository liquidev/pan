import std/macros
import std/math
import std/unicode as unicode

import aglet/rect
import cairo
import glm/vec
import stb_image/read as stbi

type
  Image* = ref object
    width*, height*: int

    surface*: ptr Surface
    surfaceBorrowed: bool
    pixelData: seq[uint8]

    cairo*: ptr Context

  Animation* = ref object
    framerate*, length*: float
    time*: float

    defaultImage*: Image
    currentImage: Image
    cairo*: ptr Context
    surface*: ptr Surface

    initialized*: bool

    pathStack: seq[ptr Path]

  Color* = object
    r*, g*, b*, a*: float

  PanLineCap* = enum
    lcButt
    lcSquare
    lcRound

  PanLineJoin* = enum
    ljMiter
    ljBevel
    ljRound

  PanAntialiasing* = enum
    aaDefault
    aaNone
    aaGray

  PanBlendMode* = enum
    bmClear
    bmSource
    bmOver
    bmIn
    bmOut
    bmAtop
    bmDest
    bmDestOver
    bmDestIn
    bmDestOut
    bmDestAtop
    bmXor
    bmAdd
    bmSaturate
    bmMultiply
    bmScreen
    bmOverlay
    bmDarken
    bmLighten
    bmColorDodge
    bmColorBurn
    bmHardLight
    bmSoftLight
    bmDifference
    bmExclusion
    bmHslHue
    bmHslSaturation
    bmHslColor
    bmHslLuminosity

  PanExtend* = enum
    NoExtend
    Repeat
    Reflect
    Pad

  PanFilter* = enum
    Nearest
    Linear

  PaintKind* = enum
    pkSolid
    pkPattern
  Paint* = object
    case kind*: PaintKind
    of pkSolid:
      color*: Color
    of pkPattern:
      patt*: ptr Pattern
      image*: Image
      extend*: Extend
      filter*: Filter
      pattMatrix*: Matrix

    lineWidth*: float
    lineCap*: LineCap
    lineJoin*: LineJoin
    antialiasing*: Antialias
    blendMode*: Operator

  PanFontWeight* = enum
    fwNormal
    fwBold
  PanFontSlant* = enum
    fsNone
    fsItalic
    fsOblique
  PanTextHAlign* = enum
    taLeft
    taCenter
    taRight
  PanTextVAlign* = enum
    taTop
    taMiddle
    taBottom
  Font* = ref object
    family*: string
    weight*: FontWeight
    slant*: FontSlant


# Color

proc initColor*(r, g, b, a: float): Color =
  Color(r: r, g: g, b: b, a: a)


# Image

proc newImage*(width, height: int): Image =
  result = Image(
    width: width, height: height,
    surface: imageSurfaceCreate(FormatArgb32, width.cint, height.cint),
  )

proc rgbaToArgb(img: var seq[byte], width, height, channels: int, premultiply: bool)

proc loadImage*(path: string): Image =

  var
    width, height, channels: int
    file: File
    magic: array[8, byte]

  doAssert open(file, path)
  discard file.readBytes(magic, 0, 8)
  file.setFilePos(0)
  var img = stbi.loadFromFile(file, width, height, channels, 4)
  file.close()

  assert channels == 4,
    "stb_image must always return an image with 4 channels, " &
    "please report this on pan's GitHub"

  # convert from RGBA to ARGB because cairo <3
  # Check for the PNG "magic" byte sequence to see if the image is a PNG.
  # If it is we need to pre-multiply alpha as PNGs are not pre-multipled
  # and Cairo requires it.
  let premultiply = magic == [0x89'u8, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  rgbaToArgb(img, width, height, channels, premultiply)

  result = Image(
    width: width, height: height,
    pixelData: move img,
  )
  result.surface = imageSurfaceCreate(
    data = cast[cstring](addr result.pixelData[0]),
    format = FormatArgb32,
    result.width.cint, result.height.cint,
    stride = result.width.cint * 4,
  )

proc rgbaToArgb(img: var seq[byte], width, height, channels: int, premultiply: bool) =
  template conversionLoop(premultiply: static bool) {.dirty.} =
    {.push checks: off.}

    for y in 0..<height:
      for x in 0..<width:
        let
          r = channels * (x + y * width)
          g = r + 1
          b = g + 1
          a = b + 1
        when premultiply:
          let
            rr: uint32 = img[r]
            gg: uint32 = img[g]
            bb: uint32 = img[b]
            aa: uint32 = img[a]
          (img[r], img[g], img[b], img[a]) =
            when cpuEndian == bigEndian:
              (img[a], byte((rr * aa + 128) div 255), byte((gg * aa + 128) div 255), byte((bb * aa + 128) div 255))
            else:
              (byte((bb * aa + 128) div 255'u32), byte((gg * aa + 128) div 255), byte((rr * aa + 128) div 255), img[a])
        else:
          (img[r], img[g], img[b], img[a]) =
            when cpuEndian == bigEndian: (img[a], img[r], img[g], img[b])
            else: (img[b], img[g], img[r], img[a])

    {.pop.}

  if premultiply:
    conversionLoop(premultiply = true)
  else:
    conversionLoop(premultiply = false)

proc getCairo(image: Image): ptr Context =
  if image.cairo.isNil:
    image.cairo = cairo.create(image.surface)
  result = image.cairo

proc destroy*(image: Image) =
  if not image.surfaceBorrowed: destroy(image.surface)
  if not image.cairo.isNil: destroy(image.cairo)


# Paint

proc defaultSettings(p: var Paint) =
  p.lineWidth = 1
  p.lineCap = LineCapButt
  p.lineJoin = LineJoinMiter
  p.antialiasing = AntialiasDefault
  p.blendMode = OperatorOver

proc solid*(color: Color): Paint =
  result = Paint(
    kind: pkSolid,
    color: color,
  )
  defaultSettings result

proc pattern*(image: Image): Paint =
  result = Paint(
    kind: pkPattern,
    patt: patternCreateForSurface(image.surface),
    image: image,
  )
  defaultSettings result
  initIdentity(addr result.pattMatrix)

proc clone(paint: Paint): Paint =

  # this must be used for all pattern paints in order to copy the pattern
  # along with the paint. unfortunately cairo doesn't just have a clone
  # method for patterns, so this mess is the result of that

  result = paint

  if paint.kind == pkPattern:
    case paint.patt.getType
    of PatternTypeSurface:
      var surface: ptr Surface
      discard paint.patt.getSurface(addr surface)
      result.patt = patternCreateForSurface(surface)
    else: assert false, "only image patterns are supported"

proc withLineWidth*(paint: Paint, newWidth: float): Paint =
  result = clone paint
  result.lineWidth = newWidth

proc withLineCap*(paint: Paint, newLineCap: PanLineCap): Paint =
  result = clone paint
  result.lineCap =
    case newLineCap
    of lcButt: LineCapButt
    of lcSquare: LineCapSquare
    of lcRound: LineCapRound

proc withLineJoin*(paint: Paint, newLineJoin: PanLineJoin): Paint =
  result = clone paint
  result.lineJoin =
    case newLineJoin
    of ljMiter: LineJoinMiter
    of ljBevel: LineJoinBevel
    of ljRound: LineJoinRound

proc withAntialiasing*(paint: Paint, newAntialiasing: PanAntialiasing): Paint =
  result = clone paint
  result.antialiasing =
    case newAntialiasing
    of aaDefault: AntialiasDefault
    of aaNone: AntialiasNone
    of aaGray: AntialiasGray

proc withBlendMode*(paint: Paint, newBlendMode: PanBlendMode): Paint =
  result = clone paint
  result.blendMode =
    case newBlendMode
    of bmClear: OperatorClear
    of bmSource: OperatorSource
    of bmOver: OperatorOver
    of bmIn: OperatorIn
    of bmOut: OperatorOut
    of bmAtop: OperatorAtop
    of bmDest: OperatorDest
    of bmDestOver: OperatorDestOver
    of bmDestIn: OperatorDestIn
    of bmDestOut: OperatorDestOut
    of bmDestAtop: OperatorDestAtop
    of bmXor: OperatorXor
    of bmAdd: OperatorAdd
    of bmSaturate: OperatorSaturate
    of bmMultiply: OperatorMultiply
    of bmScreen: OperatorScreen
    of bmOverlay: OperatorOverlay
    of bmDarken: OperatorDarken
    of bmLighten: OperatorLighten
    of bmColorDodge: OperatorColorDodge
    of bmColorBurn: OperatorColorBurn
    of bmHardLight: OperatorHardLight
    of bmSoftLight: OperatorSoftLight
    of bmDifference: OperatorDifference
    of bmExclusion: OperatorExclusion
    of bmHslHue: OperatorHslHue
    of bmHslSaturation: OperatorHslSaturation
    of bmHslColor: OperatorHslColor
    of bmHslLuminosity: OperatorHslLuminosity

proc withExtend*(paint: Paint, newExtend: PanExtend): Paint =
  result = clone paint
  if paint.kind == pkPattern:
    result.extend =
      case newExtend
      of NoExtend: ExtendNone
      of Repeat: ExtendRepeat
      of Reflect: ExtendReflect
      of Pad: ExtendPad

proc withFilter*(paint: Paint, newFilter: PanFilter): Paint =
  result = clone paint
  if paint.kind == pkPattern:
    result.filter =
      case newFilter
      of Nearest: FilterNearest
      of Linear: FilterBilinear

proc withMatrix*(paint: Paint, m: Matrix): Paint =
  result = clone paint
  if paint.kind == pkPattern:
    result.pattMatrix = m

proc destroy*(paint: Paint) =
  if paint.kind == pkPattern:
    paint.patt.destroy()

proc usePaint(anim: Animation, paint: Paint) =
  if paint.kind == pkSolid:
    anim.cairo.setSourceRgba(paint.color.r,
                             paint.color.g,
                             paint.color.b,
                             paint.color.a)
  else:
    anim.cairo.setSource(paint.patt)
    paint.patt.setExtend(paint.extend)
    paint.patt.setFilter(paint.filter)
    paint.patt.setMatrix(paint.pattMatrix.unsafeAddr)

  anim.cairo.setLineWidth(paint.lineWidth)
  anim.cairo.setLineCap(paint.lineCap)
  anim.cairo.setLineJoin(paint.lineJoin)
  anim.cairo.setAntialias(paint.antialiasing)
  anim.cairo.setOperator(paint.blendMode)


# Font

proc newFont*(family: string, weight: PanFontWeight,
              slant: PanFontSlant): Font =

  result = Font(family: family)
  result.weight =
    case weight
    of fwNormal: FontWeightNormal
    of fwBold: FontWeightBold
  result.slant =
    case slant
    of fsNone: FontSlantNormal
    of fsItalic: FontSlantItalic
    of fsOblique: FontSlantOblique

proc useFont(anim: Animation, font: Font) =
  anim.cairo.selectFontFace(font.family, font.slant, font.weight)


# Matrix

proc matrixInvert*(m: Matrix): tuple[m: Matrix, ok: bool] =
  result.m = m
  result.ok = invert(addr result.m) == StatusSuccess


# Animation

var cgLuaProcs* {.compiletime.}: seq[NimNode]

macro lua(procedure: typed): untyped =
  var procedure = procedure
  if procedure.kind == nnkSym:
    procedure = procedure.getImpl

  cgLuaProcs.add(procedure)
  result = procedure

proc clear*(anim: Animation, paint: Paint) {.lua.} =
  anim.usePaint(paint)
  anim.cairo.paint()

proc push*(anim: Animation) {.lua.} =
  anim.cairo.save()

proc pop*(anim: Animation) {.lua.} =
  anim.cairo.restore()

proc pushPath*(anim: Animation) {.lua.} =
  anim.pathStack.add(anim.cairo.copyPath())

proc popPath*(anim: Animation) {.lua.} =
  anim.cairo.newPath()
  let path = anim.pathStack.pop()
  anim.cairo.appendPath(path)
  path.destroy()

proc begin*(anim: Animation) {.lua.} =
  anim.cairo.newPath()

proc moveTo*(anim: Animation, x, y: float) {.lua.} =
  anim.cairo.moveTo(x, y)

proc lineTo*(anim: Animation, x, y: float) {.lua.} =
  anim.cairo.lineTo(x, y)

proc moveBy*(anim: Animation, dx, dy: float) {.lua.} =
  anim.cairo.relMoveTo(dx, dy)

proc relLineTo*(anim: Animation, dx, dy: float) {.lua.} =
  anim.cairo.relLineTo(dx, dy)

proc rect*(anim: Animation, x, y, w, h: float) {.lua.} =
  anim.cairo.rectangle(x, y, w, h)

proc arc*(anim: Animation, x, y, r, astart, aend: float) {.lua.} =
  anim.cairo.arc(x, y, r, astart, aend)

proc close*(anim: Animation) {.lua.} =
  anim.cairo.closePath()

proc fill*(anim: Animation, paint: Paint) {.lua.} =
  anim.usePaint(paint)
  anim.cairo.fillPreserve()

proc stroke*(anim: Animation, paint: Paint) {.lua.} =
  anim.usePaint(paint)
  anim.cairo.strokePreserve()

proc clip*(anim: Animation) {.lua.} =
  anim.cairo.clipPreserve()

proc switch*(anim: Animation): Image {.lua.} =
  anim.currentImage

proc switch*(anim: Animation, newImage: Image): Image {.lua.} =
  result = anim.currentImage
  anim.currentImage = newImage
  anim.cairo = newImage.getCairo

proc textSize*(anim: Animation, font: Font, text: string,
               size: float): tuple[w, h: float] {.lua.} =
  var
    fextents: FontExtents
    textents: TextExtents
  anim.useFont(font)
  anim.cairo.setFontSize(size)
  anim.cairo.fontExtents(addr fextents)
  anim.cairo.textExtents(text, addr textents)
  result.w = textents.width + textents.xBearing
  result.h = fextents.ascent
# lua textSize  # can't use {.lua.} here for some reason but whatever

proc addText*(anim: Animation, font: Font, text: string, size: float) {.lua.} =
  anim.useFont(font)
  anim.cairo.setFontSize(size)
  anim.cairo.textPath(text)

proc text*(anim: Animation, font: Font, x, y: float, text: string, size: float,
           w, h: float, halign: PanTextHAlign, valign: PanTextVAlign) {.lua.} =
  var (tw, th) = textSize(anim, font, text, size)
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
  anim.cairo.moveTo(tx, ty)
  anim.cairo.textPath(text)

proc translate*(anim: Animation, x, y: float) {.lua.} =
  anim.cairo.translate(x, y)

proc scale*(anim: Animation, x, y: float) {.lua.} =
  anim.cairo.scale(x, y)

proc rotate*(anim: Animation, z: float) {.lua.} =
  anim.cairo.rotate(z)

export cairo.Matrix

proc matrix*(anim: Animation): Matrix {.lua.} =
  anim.cairo.getMatrix(addr result)

proc matrix*(anim: Animation, newMatrix: Matrix): Matrix {.lua.} =
  result = anim.matrix
  anim.cairo.setMatrix(newMatrix.unsafeAddr)

proc pathCursor*(anim: Animation): tuple[x, y: float] {.lua.} =
  anim.cairo.getCurrentPoint(result[0], result[1])

proc jumpTo*(anim: Animation, time: float) =
  anim.time = time.floorMod(anim.length)

proc step*(anim: Animation, deltaTime: float) =
  anim.jumpTo(anim.time + deltaTime)

proc init*(anim: Animation, width, height: int,
           length, framerate: float) {.lua.} =
  if anim.cairo != nil: anim.cairo.destroy()
  if anim.surface != nil: anim.surface.destroy()

  anim.surface = cairo.imageSurfaceCreate(FormatArgb32, width.cint, height.cint)
  anim.cairo = cairo.create(anim.surface)
  anim.defaultImage = Image(
    width: width, height: height,
    surface: anim.surface,
    cairo: anim.cairo,
  )
  anim.currentImage = anim.defaultImage

  anim.length = length
  anim.framerate = framerate
  if anim.time > anim.length:
    anim.time = anim.time.floorMod(anim.length)

  anim.initialized = true
