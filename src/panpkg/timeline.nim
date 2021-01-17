import std/strutils

import aglet/input
import rapid/graphics
import rapid/graphics/image
import rapid/math/util
import rapid/ui

import api
import res

type
  Slider = object
    sliding: bool

  Timeline* = object
    anim*: Animation
    playing*: bool

    playIcon, pauseIcon: Sprite
    jumpToStartIcon, jumpToEndIcon: Sprite

    timeSlider: Slider

proc initTimeline*(ui: Ui, anim: Animation): Timeline =
  ## Creates and initializes a new timeline for the given animation.

  # TODO: try out pixie for SVG rendering
  const
    playIconPng = slurp("assets/icons/play.png")
    pauseIconPng = slurp("assets/icons/pause.png")
    jumpToStartIconPng = slurp("assets/icons/jumpToStart.png")
    jumpToEndIconPng = slurp("assets/icons/jumpToEnd.png")

  Timeline(
    anim: anim,
    playing: false,

    playIcon: ui.graphics.addSprite(readImage(playIconPng)),
    pauseIcon: ui.graphics.addSprite(readImage(pauseIconPng)),
    jumpToStartIcon: ui.graphics.addSprite(readImage(jumpToStartIconPng)),
    jumpToEndIcon: ui.graphics.addSprite(readImage(jumpToEndIconPng)),
  )

proc tick*(timeline: var Timeline, seconds: float32) =
  ## Ticks the timeline by ``seconds``.

  if timeline.playing:
    timeline.anim.step(seconds)

proc height*(_: type Timeline): float32 =
  ## Returns the height of the timeline in the UI.
  24

template button(ui: PanUi, bsize: Vec2f, icon: Sprite, clickAction: untyped) =
  ## Draws an icon button and processes its events.

  ui.box bsize, blFreeform:

    var drawFill = false

    ui.mouseHover:
      ui.color = hex"#ffffff20"
      drawFill = true
    ui.mouseDown mbLeft:
      ui.color = hex"#ffffff10"
      drawFill = true

    if drawFill:
      ui.fill()

    ui.drawInBox:
      let spritePosition = ui.size / 2 - icon.size.vec2f / 2
      ui.graphics.sprite(icon, spritePosition)

    ui.mouseReleased mbLeft:
      `clickAction`

proc playPause*(timeline: var Timeline) =
  timeline.playing = not timeline.playing

proc jumpToStart*(timeline: var Timeline) =
  timeline.anim.time = 0

proc jumpToEnd*(timeline: var Timeline) =
  timeline.anim.time = timeline.anim.length

proc transport(ui: PanUi, timeline: var Timeline) =

  const buttonSize = vec2f(Timeline.height)

  let playPauseButtonIcon =
    if timeline.playing: timeline.pauseIcon
    else: timeline.playIcon

  ui.button buttonSize, timeline.jumpToStartIcon: timeline.jumpToStart()
  ui.button buttonSize, playPauseButtonIcon: timeline.playPause()
  ui.button buttonSize, timeline.jumpToEndIcon: timeline.jumpToEnd()

const borderColor = hex"#ffffff20"

proc slider(ui: PanUi, slider: var Slider, size: Vec2f,
            value: var float, min, max: float) =

  ui.box size, blFreeform:
    ui.leftBorder borderColor
    ui.rightBorder borderColor

    ui.mousePressed mbLeft:
      slider.sliding = true
    if ui.mouseButtonJustReleased(mbLeft):
      slider.sliding = false

    let ctrl = ui.keyIsDown(keyLCtrl) or ui.keyIsDown(keyRCtrl)

    if slider.sliding:
      let t = clamp(ui.mousePosition.x / (ui.width - 2), 0.0, 1.0)
      value = min + t * (max - min)
      if ctrl:
        value = quantize(value, 0.25)

    ui.drawInBox:

      # slits
      let stepCount = int((max - min) * 4)
      for step in 1..<stepCount:
        let
          x = ui.width / stepCount.float * step.float
          size =
            if step mod 4 == 0: 1/2
            elif step mod 4 == 2: 1/3
            else: 1/5
          height = ui.height * size
        ui.graphics.rectangle(x, ui.height - height, 1, height, borderColor)

      # playhead
      block:
        let x = value / (max - min) * (ui.width - 2)
        ui.graphics.rectangle(x, 0, 2, ui.height, colWhite)

proc timeline(ui: PanUi, timeline: var Timeline) =

  # time
  ui.box ui.size, blHorizontal:
    ui.padH 12
    ui.font = gMono
    ui.fontHeight = 12

    let
      padding = formatFloat(timeline.anim.length, ffDecimal, 2).len
      time = formatFloat(timeline.anim.time, ffDecimal, 2).align(padding)
      len = " / " & formatFloat(timeline.anim.length, ffDecimal, 1)
      timeWidth = quantize(ui.font.textWidth(time), 4) - 4
        # ↑ this is to prevent it from jerkin' around because of
        # textWidth imprecision
      lenWidth = ui.font.textWidth(len) + 8

    # current
    ui.box vec2f(timeWidth, ui.height + 1), blFreeform:
      ui.text(time, colWhite, (apLeft, apMiddle))
    # total
    ui.box vec2f(lenWidth, ui.height + 1), blFreeform:
      ui.text(len, colWhite.withAlpha(0.6), (apLeft, apMiddle))

    # time slider
    ui.box vec2f(ui.width - ui.x, ui.height), blFreeform:
      ui.slider(
        timeline.timeSlider, ui.size,
        value = timeline.anim.time,
        min = 0, max = timeline.anim.length,
      )

proc keyShortcuts(ui: PanUi, timeline: var Timeline) =

  if ui.keyJustPressed(keySpace):
    timeline.playPause()

  let
    shift = ui.keyIsDown(keyLShift) or ui.keyIsDown(keyRShift)
    ctrl = ui.keyIsDown(keyLCtrl) or ui.keyIsDown(keyRCtrl)

  if shift:
    var changed = false
    if ui.keyJustTyped(keyLeft):
      timeline.anim.step(-0.25)
      changed = true
    if ui.keyJustTyped(keyRight):
      timeline.anim.step(0.25)
      changed = true
    if changed:
      timeline.anim.time = quantize(timeline.anim.time, 0.25)

  elif ctrl:
    if ui.keyJustPressed(keyLeft):
      timeline.jumpToStart()
    if ui.keyJustPressed(keyRight):
      timeline.jumpToEnd()

  else:
    let frame = 1 / timeline.anim.framerate
    if ui.keyJustTyped(keyLeft):
      timeline.anim.step(-frame)
    if ui.keyJustTyped(keyRight):
      timeline.anim.step(frame)

proc timelineBar*(ui: PanUi, timeline: var Timeline) =
  ## Draws the timeline and processes its events.

  ui.box vec2f(ui.width, Timeline.height), blHorizontal:
    ui.fill hex"#202020"
    ui.topBorder borderColor

    ui.mouseOverBar = ui.mouseInBox

    ui.transport(timeline)

    ui.box vec2f(ui.width - ui.x, Timeline.height), blFreeform:
      ui.fill hex"#191919"
      ui.leftBorder borderColor
      ui.timeline(timeline)

  ui.keyShortcuts(timeline)
