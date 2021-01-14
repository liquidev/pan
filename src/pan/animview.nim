import aglet
import cairo
import rapid/graphics
import rapid/ui
import api
import res

const
  ZoomLevels = [
    0.05, 0.1, 0.25, 0.5, 0.75, 1.0,
    1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0,
    12.5, 15.0, 17.5, 20.0
  ]
  Zoom100 = 5

type
  AnimationView* = object
    anim*: Animation

    textureTime: float  # the time for which the texture was rendered
    texture: Texture2D[Rgba8]

    zoomLevel: int
    zoomLevelHudEndTime: float
    panning: bool
    pan: Vec2f  # haha, get it?

proc initAnimationView*(ui: PanUi, anim: Animation): AnimationView =
  ## Creates and initializes a new animation view.

  result = AnimationView(
    anim: anim,
    textureTime: -1234,  # just some easily recognizable value in case of error
    texture: ui.graphics.window.newTexture2D[:Rgba8](),
    zoomLevel: Zoom100,
    zoomLevelHudEndTime: -0.1,
  )

  # cairo operates on ARGB, but OpenGL wants RGBA, so we need to apply a
  # swizzle mask to convert between them
  when cpuEndian == bigEndian:
    result.texture.swizzleMask = [ccGreen, ccBlue, ccAlpha, ccRed]
  else:
    # on little endian channels are ordered as BGRA
    result.texture.swizzleMask = [ccBlue, ccGreen, ccRed, ccAlpha]

proc updateTexture*(av: var AnimationView) =
  ## Updates the displayed texture to the current animation frame.

  if av.anim.initialized:
    if av.textureTime != av.anim.time:
      let
        size = vec2i(av.anim.surface.getWidth, av.anim.surface.getHeight)
        data = cast[ptr Rgba8](av.anim.surface.getData)
      av.texture.upload(size, data)
      av.textureTime = av.anim.time

proc zoom*(av: AnimationView): float32 =
  ## Returns the animation view's zoom level.
  ZoomLevels[av.zoomLevel]

proc animationView*(ui: PanUi, av: var AnimationView, size: Vec2f) =
  ## Draws an animation view and processes its events.

  av.updateTexture()

  ui.box size, blFreeform:

    # rendering

    ui.drawInBox:
      let
        oldBatch = ui.graphics.currentBatch
        textureSize = av.texture.size.vec2f
        rect = rectf(vec2f(0, 0), textureSize)

      ui.graphics.batchNewSampler av.texture.sampler(
        minFilter = fmLinear,
        magFilter = fmNearest,
      )

      ui.graphics.transform:
        ui.graphics.translate(ui.size / 2)
        ui.graphics.scale(av.zoom)
        ui.graphics.translate(-textureSize / 2)
        ui.graphics.translate(av.pan)
        ui.graphics.rawRectangle(rect)

      ui.graphics.batchNewCopy(oldBatch)

    # ok zoomer

    let previousZoomLevel = av.zoomLevel

    av.zoomLevel += ui.scroll.y.int
    av.zoomLevel = av.zoomLevel.clamp(ZoomLevels.low, ZoomLevels.high)

    ui.mousePressed mbRight:
      av.zoomLevel = Zoom100
      reset av.pan

    if av.zoomLevel != previousZoomLevel:
      av.zoomLevelHudEndTime = timeInSeconds() + 1.5

    # ok panner

    ui.mousePressed mbMiddle:
      av.panning = true
    if ui.mouseButtonJustReleased(mbMiddle):
      av.panning = false

    if av.panning:
      av.pan += ui.deltaMousePosition / av.zoom

    # zoom HUD

    if timeInSeconds() < av.zoomLevelHudEndTime:
      let zoomPercent = $int(av.zoom * 100) & '%'
      ui.pad 8
      ui.box vec2f(16 + ui.font.textWidth(zoomPercent), 24), blFreeform:
        ui.align (apRight, apTop)
        ui.fill hex"#0000007f"
        ui.pad 8
        ui.text(zoomPercent, colWhite, (apLeft, apMiddle))
