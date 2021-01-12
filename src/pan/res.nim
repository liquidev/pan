import rapid/graphics
import rapid/ui

import api

type
  PanUi* = ref object of Ui
    mouseOverBar*: bool

var
  gSans*, gSansBold*: graphics.Font
  gAnim*: Animation
