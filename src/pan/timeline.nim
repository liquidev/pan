import rapid/graphics
import rapid/ui

import api

type
  Timeline* = object
    playing*: bool
    time*: float32

proc tick*(timeline: var Timeline, seconds: float32) =
  ## Ticks the timeline by ``seconds``.
  timeline.time += seconds * float32(timeline.playing)
