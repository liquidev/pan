import std/strutils

import rapid/gfx
import rapid/gfx/text
import rapid/res/images
import rapid/res/textures
import rdgui/button
import rdgui/control
import rdgui/event
import rdgui/layout

import api
import res

type
  IconButton = ref object of Button
    icon: RTexture

  Timeline* = ref object of Box
    fWidth: float
    anim*: Animation
    playback*: PlaybackModule

  TimelineModule = ref object of Control
    timeline: Timeline

  PlaybackModule* = ref object of TimelineModule
    playing*: bool

    buttonBox: Box

    # dynamically changing elements
    iconPlay, iconPause: RTexture
    bPlayPause: IconButton

# IconButton implementation

IconButton.renderer(Pan, button):
  if button.hasMouse:
    ctx.begin()
    ctx.color =
      if button.pressed: gray(255, 16)
      else: gray(255, 32)
    ctx.rect(0, 0, button.width, button.height)
    ctx.draw()
  ctx.color = gray(255)
  ctx.begin()
  ctx.texture = button.icon
  ctx.rect(0, 0, button.width, button.height)
  ctx.draw()
  ctx.noTexture()

proc initIconButton(button: IconButton, x, y, width, height: float,
                    icon: RTexture, rend = IconButtonPan) =
  button.initButton(x, y, width, height, rend)
  button.icon = icon

proc newIconButton(x, y, width, height: float, icon: RTexture,
                   rend = IconButtonPan): IconButton =
  new(result)
  result.initIconButton(x, y, width, height, icon, rend)


# TimelineModule implementation

method layout(tm: TimelineModule) {.base.} = discard

method width(tm: TimelineModule): float = tm.timeline.width
method height(tm: TimelineModule): float = 24

proc anim(tm: TimelineModule): Animation = tm.timeline.anim

TimelineModule.renderer(Default, tm):
  ctx.begin()
  ctx.color = gray(32)
  ctx.rect(0, 0, tm.width, tm.height)
  ctx.color = gray(255, 32)
  ctx.rect(0, 0, tm.width, 1)
  ctx.draw()


# PlaybackModule implementation

method layout(pm: PlaybackModule) =
  pm.buttonBox.pos = vec2(pm.width / 2 - pm.buttonBox.width / 2, 0.0)

proc tick*(pm: PlaybackModule, deltaTime: float) =
  if pm.playing:
    pm.anim.step(deltaTime)

proc playPause*(pm: PlaybackModule) =
  pm.playing = not pm.playing
  pm.bPlayPause.icon =
    if pm.playing: pm.iconPause
    else: pm.iconPlay

proc jumpToStart*(pm: PlaybackModule) =
  pm.anim.time = 0

proc jumpToEnd*(pm: PlaybackModule) =
  pm.anim.time = pm.anim.length

{.push warning[LockLevel]: off.}

method onEvent*(pm: PlaybackModule, event: UiEvent) =

  pm.buttonBox.event(event)
  if event.consumed: return

  case event.kind
  of evKeyPress, evKeyRepeat:
    case event.key
    of keySpace:
      pm.playPause()
      event.consume()
    of keyLeft, keyRight:
      if mkShift in event.modKeys:
        if event.key == keyLeft: pm.jumpToStart()
        else: pm.jumpToEnd()
      else:
        let dir =
          if event.key == keyLeft: -1.float
          else: 1.float
        pm.anim.step(1 / pm.anim.framerate * dir)
      event.consume()
    else: discard
  of evMousePress:
    if pm.hasMouse:
      event.consume()
  else: discard

{.pop.}

PlaybackModule.renderer(Default, pm):
  # background
  TimelineModuleDefault(ctx, step, pm)

  # time
  let
    timeText = formatFloat(pm.anim.time, ffDecimal, 2)
    lenText = formatFloat(pm.anim.length, ffDecimal, 1)
    lenPos = gSansBold.widthOf(timeText) + 16
  ctx.color = gray(255)
  ctx.text(gSansBold, 4, 4, timeText)
  ctx.text(gSans, 4 + lenPos, 4, "/  " & lenText)

  # buttons
  pm.buttonBox.draw(ctx, step)

proc initPlaybackModule*(pm: PlaybackModule, tl: Timeline, x, y: float) =
  pm.initControl(x, y, PlaybackModuleDefault)
  pm.timeline = tl

  const
    IconPlayPng = slurp("assets/icons/play.png")
    IconPausePng = slurp("assets/icons/pause.png")
    JumpToStartPng = slurp("assets/icons/jumpToStart.png")
    JumpToEndPng = slurp("assets/icons/jumpToEnd.png")
  pm.iconPlay = newRTexture(readRImagePng(IconPlayPng))
  pm.iconPause = newRTexture(readRImagePng(IconPausePng))
  let
    iconJumpToStart = newRTexture(readRImagePng(JumpToStartPng))
    iconJumpToEnd = newRTexture(readRImagePng(JumpToEndPng))

  pm.buttonBox = newBox(0, 0)
  pm.bPlayPause = newIconButton(0, 0, 24, 24, pm.iconPlay, IconButtonPan)
  var
    jumpToStart = newIconButton(0, 0, 24, 24, iconJumpToStart, IconButtonPan)
    jumpToEnd = newIconButton(0, 0, 24, 24, iconJumpToEnd, IconButtonPan)

  pm.bPlayPause.onClick = proc () =
    pm.playPause()

  jumpToStart.onClick = proc () =
    pm.jumpToStart()

  jumpToEnd.onClick = proc () =
    pm.jumpToEnd()

  pm.onContain do ():
    pm.contain(pm.buttonBox)
    pm.buttonBox.add(jumpToStart)
    pm.buttonBox.add(pm.bPlayPause)
    pm.buttonBox.add(jumpToEnd)
    pm.buttonBox.listHorizontal(0, 0)

proc newPlaybackModule*(x, y: float, tl: Timeline): PlaybackModule =
  new(result)
  result.initPlaybackModule(tl, x, y)


# Timeline implementation

method width*(tl: Timeline): float = tl.fWidth

proc `width=`*(tl: Timeline, newWidth: float) =
  tl.fWidth = newWidth
  for child in tl.children:
    if child of PlaybackModule:
      child.PlaybackModule.layout()

proc initTimeline*(tl: Timeline, x, y, width: float, anim: Animation) =
  tl.initBox(x, y, BoxChildren)
  tl.width = width
  tl.anim = anim

  tl.playback = newPlaybackModule(0, 0, tl)

  tl.onContain do:
    tl.add(tl.playback)
    tl.listVertical(0, 0)

proc newTimeline*(x, y, width: float, anim: Animation): Timeline =
  new(result)
  result.initTimeline(x, y, width, anim)
