import std/math

import cairo

type
  Animation* = ref object
    framerate*, length*: float
    time*: float

    cairo*: ptr Context
    surface*: ptr Surface

    initialized*: bool

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

  PaintKind* = enum
    pkSolid
    pkPattern
  Paint* = object
    case kind*: PaintKind
    of pkSolid:
      color*: Color
    of pkPattern:
      patt*: ptr Pattern

    lineWidth*: float
    lineCap*: LineCap
    lineJoin*: LineJoin

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
  Font* = object
    family*: string
    weight*: FontWeight
    slant*: FontSlant



# Color

proc initColor*(r, g, b, a: float): Color =
  Color(r: r, g: g, b: b, a: a)


# Paint

proc solid*(color: Color): Paint =
  Paint(kind: pkSolid,
        color: color,
        lineWidth: 1,
        lineCap: LineCapButt,
        lineJoin: LineJoinMiter)

proc lineWidth*(paint: Paint, newWidth: float): Paint =
  result = paint
  result.lineWidth = newWidth

proc lineCap*(paint: Paint, newLineCap: PanLineCap): Paint =
  result = paint
  result.lineCap =
    case newLineCap
    of lcButt: LineCapButt
    of lcSquare: LineCapSquare
    of lcRound: LineCapRound

proc lineJoin*(paint: Paint, newLineJoin: PanLineJoin): Paint =
  result = paint
  result.lineJoin =
    case newLineJoin
    of ljMiter: LineJoinMiter
    of ljBevel: LineJoinBevel
    of ljRound: LineJoinRound

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
  anim.cairo.setLineWidth(paint.lineWidth)
  anim.cairo.setLineCap(paint.lineCap)
  anim.cairo.setLineJoin(paint.lineJoin)


# Font

proc font*(family: string, weight: PanFontWeight,
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


# Animation

var cgLuaProcs* {.compiletime.}: seq[NimNode]

macro lua(procedure: typed) =
  cgLuaProcs.add(procedure)

proc clear*(anim: Animation, paint: Paint) {.lua.} =
  anim.usePaint(paint)
  anim.cairo.paint()

proc push*(anim: Animation) {.lua.} =
  anim.cairo.save()

proc pop*(anim: Animation) {.lua.} =
  anim.cairo.restore()

proc begin*(anim: Animation) {.lua.} =
  anim.cairo.newPath()

proc moveTo*(anim: Animation, x, y: float) {.lua.} =
  anim.cairo.moveTo(x, y)

proc lineTo*(anim: Animation, x, y: float) {.lua.} =
  anim.cairo.lineTo(x, y)

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

proc textSize*(anim: Animation, font: Font, text: string, size: float,
               w, h: var float) {.lua.} =
  var
    fextents: FontExtents
    textents: TextExtents
  anim.useFont(font)
  anim.cairo.setFontSize(size)
  anim.cairo.fontExtents(addr fextents)
  anim.cairo.textExtents(text, addr textents)
  w = textents.width + textents.xBearing
  h = fextents.ascent

proc text*(anim: Animation, font: Font, x, y: float, text: string, size: float,
           w, h: float, halign: PanTextHAlign, valign: PanTextVAlign) {.lua.} =
  var tw, th: float
  anim.textSize(font, text, size, tw, th)
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

proc pathPoint*(anim: Animation, x, y: var float) {.lua.} =
  anim.cairo.getCurrentPoint(x, y)

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

  anim.length = length
  anim.framerate = framerate
  if anim.time > anim.length:
    anim.time = anim.time.floorMod(anim.length)

  anim.initialized = true
