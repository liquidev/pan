import aglet
import cairo
import rapid/graphics
import rapid/graphics/meshes
import rapid/graphics/vertex_types
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

proc initAnimationView*(ui: PanUi, anim: Animation): AnimationView =
  ## Creates and initializes a new animation view.

  result = AnimationView(
    anim: anim,
    textureTime: -1234,  # just some easily recognizable value in case of error
    texture: ui.graphics.window.newTexture2D[:Rgba8]()
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

proc animationView*(ui: PanUi, av: var AnimationView, size: Vec2f) =
  ## Draws an animation view and processes its events.

  av.updateTexture()

  ui.box size, blFreeform:
    ui.drawInBox:
      let
        oldBatch = ui.graphics.currentBatch
        textureSize = av.texture.size.vec2f
        rect = rectf(ui.size / 2 - textureSize / 2, av.texture.size.vec2f)

      ui.graphics.batchNewSampler av.texture.sampler(
        minFilter = fmLinear,
        magFilter = fmNearest,
      )
      ui.graphics.rawRectangle(rect)
      ui.graphics.batchNewCopy(oldBatch)
