import rapid/gfx
import rapid/gfx/text
import rapid/res/textures
import rdgui/control
import rdgui/event

import res

type
  ImageView* = ref object of Control
    fWidth, fHeight: float
    image*: RTexture
    scrolling: bool
    scroll: Vec2[float]
    zoom: float
    lastZoomTime: float

method width*(view: ImageView): float = view.fWidth
method height*(view: ImageView): float = view.fHeight

proc `width=`*(view: ImageView, newWidth: float) =
  view.fWidth = newWidth
proc `height=`*(view: ImageView, newHeight: float) =
  view.fHeight = newHeight

{.push warning[LockLevel]: off.}

method onEvent*(view: ImageView, event: UiEvent) =
  if event.kind in {evMousePress, evMouseRelease}:
    view.scrolling = event.kind == evMousePress and
                     event.mouseButton == mb3
    if view.scrolling:
      event.consume()
    if event.kind == evMouseRelease and event.mouseButton == mb2:
      view.zoom = 1
      view.lastZoomTime = time()
  elif event.kind == evMouseScroll:
    view.zoom *= 1 - (-event.scrollPos.y * 0.5)
    view.lastZoomTime = time()
  if view.scrolling and event.kind == evMouseMove:
    view.scroll += (event.mousePos - view.lastMousePos) / view.zoom

{.pop.}

ImageView.renderer(Default, view):
  ctx.transform:
    ctx.translate(view.width / 2, view.height / 2)
    ctx.scale(view.zoom, view.zoom)
    ctx.translate(-view.image.width / 2, -view.image.height / 2)
    ctx.translate(view.scroll.x, view.scroll.y)
    ctx.begin()
    ctx.texture = view.image
    ctx.rect(0, 0, view.image.width.float, view.image.height.float)
    ctx.draw()
    ctx.noTexture()
  if time() - view.lastZoomTime in 0.0..1.5:
    let zoomPercent = $int(view.zoom * 100) & "%"
    ctx.begin()
    ctx.color = gray(0, 128)
    ctx.rect(view.width - 24 - gSans.widthOf(zoomPercent), 8,
             16 + gSans.widthOf(zoomPercent), 24)
    ctx.draw()
    ctx.color = gray(255)
    ctx.text(gSans, view.width - 16, 12, zoomPercent, halign = taRight)

proc initImageView*(view: ImageView, x, y, width, height: float,
                    image: RTexture) =
  view.initControl(x, y, ImageViewDefault)
  view.width = width
  view.height = height
  view.image = image
  view.zoom = 1.0

proc newImageView*(x, y, width, height: float, image: RTexture): ImageView =
  new(result)
  result.initImageView(x, y, width, height, image)
