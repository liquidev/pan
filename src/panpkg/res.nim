import std/monotimes
import std/times

import rapid/graphics
import rapid/ui

import api

type
  PanUi* = ref object of Ui
    mouseOverBar*: bool

var
  gSans*, gMono*: graphics.Font
  gAnim*: Animation

let gProcessStartTime = getMonoTime()

proc timeInSeconds*(): float =
  inMilliseconds(getMonoTime() - gProcessStartTime).float / 1_000
