import cairo
import rapid/gfx
import rapid/gfx/text
import rapid/res/textures
import rdgui/control
import rdgui/event

import api
import res

type
  AnimationView* = ref object of Control
    fWidth, fHeight: float
    anim*: Animation
    surfaceDrawProgram: RProgram
    texture: RTexture
    scrolling: bool
    scroll: Vec2[float]
    zoomLevel: int
    lastZoomTime: float

const
  ZoomLevels = [
    0.05, 0.1, 0.25, 0.5, 0.75, 1.0,
    1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0,
    12.5, 15.0, 17.5, 20.0
  ]
  Zoom100 = 5

method width*(view: AnimationView): float = view.fWidth
method height*(view: AnimationView): float = view.fHeight

proc `width=`*(view: AnimationView, newWidth: float) =
  view.fWidth = newWidth
proc `height=`*(view: AnimationView, newHeight: float) =
  view.fHeight = newHeight

proc zoom(view: AnimationView): float = ZoomLevels[view.zoomLevel]

{.push warning[LockLevel]: off.}

method onEvent*(view: AnimationView, event: UiEvent) =
  if event.kind in {evMousePress, evMouseRelease}:
    view.scrolling = event.kind == evMousePress and
                     event.mouseButton == mb3
    if view.scrolling:
      event.consume()
    if event.kind == evMouseRelease and event.mouseButton == mb2:
      view.scroll = vec2(0.0, 0.0)
      view.zoomLevel = Zoom100
      view.lastZoomTime = time()
      event.consume()
  elif event.kind == evMouseScroll:
    view.zoomLevel += event.scrollPos.y.int
    view.zoomLevel = view.zoomLevel.clamp(ZoomLevels.low, ZoomLevels.high)
    view.lastZoomTime = time()
  if view.scrolling and event.kind == evMouseMove:
    view.scroll += (event.mousePos - view.lastMousePos) / view.zoom

{.pop.}

proc updateTexture(view: AnimationView) =
  if view.texture == nil:
    view.texture = newRTexture(1, 1, (fltLinear, fltNearest,
                                      wrapClampToEdge, wrapClampToEdge))
  if view.anim.initialized:
    var data = view.anim.surface.getData()
    view.texture.update(view.anim.surface.getWidth(),
                        view.anim.surface.getHeight(),
                        data, dataFormat = fmtUint32r8g8b8a8)

AnimationView.renderer(Default, view):

  # initialize the surface draw shader program
  if view.surfaceDrawProgram == nil:
    view.surfaceDrawProgram = ctx.gfx.newRProgram(
      RDefaultVshSrc,
      """
      vec4 rFragment(vec4 col, sampler2D tex, vec2 pos, vec2 uv) {
        uv.y = 1.0 - uv.y;
        return rTexel(tex, uv).gbar * col;
      }
      """,
    )

  view.updateTexture()

  # draw the surface texture
  ctx.transform:
    ctx.translate(view.width / 2, view.height / 2)
    ctx.scale(view.zoom, view.zoom)
    ctx.translate(-view.texture.width / 2, -view.texture.height / 2)
    ctx.translate(view.scroll.x, view.scroll.y)
    ctx.begin()
    ctx.program = view.surfaceDrawProgram
    ctx.texture = view.texture
    ctx.rect(0, 0, view.texture.width.float, view.texture.height.float)
    ctx.draw()
    ctx.noTexture()
    ctx.defaultProgram()

  if time() - view.lastZoomTime in 0.0..1.5:
    let zoomPercent = $int(view.zoom * 100) & "%"
    ctx.begin()
    ctx.color = gray(0, 128)
    ctx.rect(view.width - 24 - gSans.widthOf(zoomPercent), 8,
             16 + gSans.widthOf(zoomPercent), 24)
    ctx.draw()
    ctx.color = gray(255)
    ctx.text(gSans, view.width - 16, 12, zoomPercent, halign = text.taRight)

proc initAnimationView*(view: AnimationView, x, y, width, height: float,
                        anim: Animation) =
  view.initControl(x, y, AnimationViewDefault)
  view.width = width
  view.height = height
  view.anim = anim
  view.zoomLevel = Zoom100

proc newAnimationView*(x, y, width, height: float,
                       anim: Animation): AnimationView =
  new(result)
  result.initAnimationView(x, y, width, height, anim)
