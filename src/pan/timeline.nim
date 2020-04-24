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
    groups*: GroupsModule

  TimelineModule = ref object of Control
    timeline: Timeline

  PlaybackModule* = ref object of TimelineModule
    playing*: bool

    buttonBox: Box

    # dynamically changing elements
    iconPlay, iconPause: RTexture
    bPlayPause: IconButton

  GroupsModule* = ref object of TimelineModule
    # GroupsModule is a bit of a misnomer because it also handles the timeline
    # itself. however I could not come up with a better name, so uhh… this is
    # the result.
    # this also handles scrubbing.

    scroll: Vec2[float]
    zoom: float
    scrolling, scrubbing: bool

    # dynamically changing elements
    iconChevronRight, iconChevronUp: RTexture
    bShowHide: IconButton
    viewer: GroupViewer

  GroupViewer = ref object of Control
    gm: GroupsModule

    fHeight: float
    groups: seq[MarkerGroup]

  MarkerGroup* = ref object
    label*: string
    markers*: seq[Marker]
    areas*: seq[Area]
  MarkerKind* = enum
    mkSquare
    mkDiamond
    mkCircle
  Marker* = tuple
    kind: MarkerKind
    time: float
  Area* = tuple
    area: Slice[float]


{.push warning[LockLevel]: off.}


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
  ctx.rect(button.width / 2 - button.icon.width / 2,
           button.height / 2 - button.icon.height / 2,
           button.icon.width.float, button.icon.height.float)
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

method onEvent(tm: TimelineModule, event: UiEvent) =
  if event.kind == evMousePress and tm.hasMouse:
    event.consume()

TimelineModule.renderer(Default, tm):
  ctx.begin()
  ctx.color = gray(32)
  ctx.rect(0, 0, tm.width, tm.height)
  ctx.color = gray(255, 32)
  ctx.rect(0, 0, tm.width, 1)
  ctx.draw()

proc initTimelineModule(tm: TimelineModule, tl: Timeline, x, y: float,
                        rend: ControlRenderer) =
  tm.initControl(x, y, rend)
  tm.timeline = tl


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
  else: discard

  procCall pm.TimelineModule.onEvent(event)

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
  pm.initTimelineModule(tl, x, y, PlaybackModuleDefault)

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

proc newPlaybackModule*(tl: Timeline, x, y: float): PlaybackModule =
  new(result)
  result.initPlaybackModule(tl, x, y)


# GroupsModule implementation

proc mapRange(x: float, u, v: Slice[float]): float =
  result = v.a + (x - u.a) / (u.b - u.a) * (v.b - v.a)

proc toggle*(gm: GroupsModule) =
  gm.viewer.visible = not gm.viewer.visible
  gm.bShowHide.icon =
    if gm.viewer.visible: gm.iconChevronUp
    else: gm.iconChevronRight

proc timelineWidth(gm: GroupsModule): float =
  gm.width - gm.bShowHide.width

proc timelineX(gm: GroupsModule): float =
  gm.bShowHide.width

proc timelineHasMouse(gm: GroupsModule): bool =
  gm.mouseInRect(gm.timelineX, 0, gm.timelineWidth, gm.height)

proc timeAreaWidth(gm: GroupsModule, time: float): float =
  (time + gm.scroll.x) * gm.zoom * gm.timelineWidth

proc timeToCoords(gm: GroupsModule, time: float): float =
  gm.timelineWidth / 2 - gm.timeAreaWidth(gm.anim.length) / 2 +
  gm.timeAreaWidth(time)

GroupViewer.renderer(Default, viewer):
  # background
  ctx.begin()
  ctx.color = gray(24, 192)
  ctx.rect(0, 0, viewer.width, viewer.height)
  ctx.color = gray(255, 32)
  ctx.rect(0, 0, viewer.width, 1)
  ctx.draw()

method width(viewer: GroupViewer): float = viewer.gm.width
method height(viewer: GroupViewer): float = viewer.fHeight

proc `height=`(viewer: GroupViewer, newHeight: float) =
  viewer.fHeight = newHeight
  echo viewer.isNil
  echo viewer.gm.isNil
  viewer.pos.y = -viewer.height

proc initGroupViewer(viewer: GroupViewer, gm: GroupsModule, x, y: float) =
  viewer.initControl(x, y, GroupViewerDefault)
  viewer.gm = gm
  viewer.height = 128

proc newGroupViewer(gm: GroupsModule, x, y: float): GroupViewer =
  new(result)
  result.initGroupViewer(gm, x, y)

proc newGroup*(gm: GroupsModule, label: string): MarkerGroup =
  result = MarkerGroup(label: label)
  gm.viewer.groups.add(result)

proc resetGroups*(gm: GroupsModule) =
  gm.viewer.groups.setLen(0)

proc square*(group: MarkerGroup, time: float) =
  group.markers.add (kind: mkSquare, time: time)

proc diamond*(group: MarkerGroup, time: float) =
  group.markers.add (kind: mkDiamond, time: time)

proc circle*(group: MarkerGroup, time: float) =
  group.markers.add (kind: mkCircle, time: time)

proc area*(group: MarkerGroup, startTime, endTime: float) =
  group.areas.add (area: startTime..endTime)

proc scrub(gm: GroupsModule, mouseX: float) =
  let
    startX = gm.timeToCoords(0)
    endX = gm.timeToCoords(gm.anim.length)
    time = mapRange(mouseX - gm.timelineX,
                    startX..endX, 0.0..gm.anim.length)
  gm.anim.jumpTo(time)

method onEvent*(gm: GroupsModule, event: UiEvent) =

  gm.bShowHide.event(event)
  if event.consumed: return

  if event.kind in {evMousePress, evMouseRelease}:
    if gm.timelineHasMouse and event.kind == evMousePress:
      gm.scrolling = event.mouseButton == mb3
      gm.scrubbing = event.mouseButton == mb1
      if gm.scrolling or gm.scrubbing:
        event.consume()
      if gm.scrubbing:
        gm.scrub(event.mousePos.x)
    else:
      gm.scrolling = false
      gm.scrubbing = false
  elif event.kind == evMouseScroll and gm.timelineHasMouse:
    gm.zoom *= (1 + event.scrollPos.y * 0.1)
    event.consume()
  elif gm.scrolling and event.kind == evMouseMove:
    let
      startX = gm.timeAreaWidth(0)
      endX = gm.timeAreaWidth(1)
      dx = event.mousePos.x - gm.lastMousePos.x
      dt = dx / (endX - startX)
    gm.scroll.x += dt * 2
  elif gm.scrubbing and event.kind == evMouseMove:
    gm.scrub(event.mousePos.x)

  procCall gm.TimelineModule.onEvent(event)

GroupsModule.renderer(Default, gm):
  # background
  TimelineModuleDefault(ctx, step, gm)

  # timeline
  ctx.transform:
    let screenPos = gm.screenPos
    ctx.scissor(screenPos.x + gm.bShowHide.width, screenPos.y,
                gm.timelineWidth, gm.height):
      ctx.translate(gm.bShowHide.width, 0)

      # background
      ctx.begin()
      ctx.color = gray(16)
      ctx.rect(0, 0, gm.timelineWidth, gm.height)
      let
        startX = gm.timeToCoords(0)
        endX = gm.timeToCoords(gm.anim.length)
        pixelsPerSecond = (endX - startX) / gm.anim.length
      ctx.color = gray(24)
      ctx.rect(startX, 0, endX - startX, gm.height)
      ctx.color = gray(255, 32)
      ctx.rect(startX, 1, 1, gm.height - 1)
      ctx.rect(endX, 1, 1, gm.height - 1)
      for s in 1..<gm.anim.length.int * 10:
        let x = gm.timeToCoords(s / 10)
        if pixelsPerSecond > 6 and s mod 10 == 0:
          ctx.rect(x, gm.height / 2, 1, gm.height / 2)
        elif pixelsPerSecond > 12 and s mod 5 == 0:
          ctx.rect(x, 2 * gm.height / 3, 1, gm.height / 3)
        elif pixelsPerSecond > 48:
          ctx.rect(x, 5 * gm.height / 6, 1, gm.height / 6)
      ctx.draw()

      # playhead
      const PlayheadColor = hex"#4493A6"
      let playheadX = round(gm.timeToCoords(gm.anim.time))
      ctx.begin()
      ctx.color = PlayheadColor
      ctx.rect(playheadX, 0, 1, gm.height)
      ctx.transform:
        const TriSize = 4.0
        ctx.translate(playheadX + 1, gm.height)
        ctx.tri((0.0, -TriSize), (-TriSize, 0.0), (TriSize, 0.0))
      ctx.draw()

      # border
      ctx.begin()
      ctx.color = gray(255, 32)
      ctx.rect(0, 0, gm.timelineWidth, 1)
      ctx.draw()

  # groups
  gm.viewer.draw(ctx, step)

  ctx.color = gray(255)

  # sub-controls
  gm.bShowHide.draw(ctx, step)

proc initGroupsModule*(gm: GroupsModule, tl: Timeline, x, y: float) =
  gm.initTimelineModule(tl, x, y, GroupsModuleDefault)

  if gm.anim.initialized:
    gm.zoom = 1 / (gm.anim.length + 1)
  else:
    gm.zoom = 1 / 6

  const
    IconChevronRightPng = slurp("assets/icons/chevronRight.png")
    IconChevronUpPng = slurp("assets/icons/chevronUp.png")
  gm.iconChevronRight = newRTexture(readRImagePng(IconChevronRightPng))
  gm.iconChevronUp = newRTexture(readRImagePng(IconChevronUpPng))

  gm.bShowHide = newIconButton(0, 0, 24, 24, gm.iconChevronRight)
  gm.bShowHide.onClick = proc () =
    gm.toggle()

  gm.viewer = gm.newGroupViewer(0, 0)
  gm.viewer.visible = false

  gm.onContain do:
    gm.contain(gm.bShowHide)
    gm.contain(gm.viewer)

proc newGroupsModule*(tl: Timeline, x, y: float): GroupsModule =
  new(result)
  result.initGroupsModule(tl, x, y)


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

  tl.playback = newPlaybackModule(tl, 0, 0)
  tl.groups = newGroupsModule(tl, 0, 0)

  tl.onContain do:
    tl.add(tl.groups)
    tl.add(tl.playback)
    tl.listVertical(0, 0)

proc newTimeline*(x, y, width: float, anim: Animation): Timeline =
  new(result)
  result.initTimeline(x, y, width, anim)


{.pop.}
