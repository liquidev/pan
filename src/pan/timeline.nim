import std/strutils

import aglet/input
import rapid/graphics
import rapid/graphics/image
import rapid/math/util
import rapid/ui

import api
import res

type
  Timeline* = object
    anim*: Animation
    playing*: bool

    playIcon, pauseIcon: Sprite
    jumpToStartIcon, jumpToEndIcon: Sprite

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

    playIcon: ui.graphics.addSprite(readPngImage(playIconPng)),
    pauseIcon: ui.graphics.addSprite(readPngImage(pauseIconPng)),
    jumpToStartIcon: ui.graphics.addSprite(readPngImage(jumpToStartIconPng)),
    jumpToEndIcon: ui.graphics.addSprite(readPngImage(jumpToEndIconPng)),
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

proc timeline(ui: PanUi, timeline: var Timeline) =

  # time
  ui.box ui.size, blHorizontal:
    ui.padH 8

    let
      time = formatFloat(timeline.anim.time, ffDecimal, 2)
      len = "/  " & formatFloat(timeline.anim.length, ffDecimal, 1)
      timeWidth = quantize(gSansBold.textWidth(time) + 16, 16)

    # current
    ui.box vec2f(timeWidth, ui.height), blFreeform:
      ui.font = gSansBold
      ui.text(time, colWhite, (apLeft, apMiddle))
    # total
    ui.box ui.size, blFreeform:
      ui.text(len, colWhite, (apLeft, apMiddle))

proc keyShortcuts(ui: PanUi, timeline: var Timeline) =

  if ui.keyJustPressed(keySpace):
    timeline.playPause()

  let shift = ui.keyIsDown(keyLShift) or ui.keyIsDown(keyRShift)

  if shift:
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

  const borderColor = hex"#ffffff20"

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
