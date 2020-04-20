# Package

version       = "0.1.0"
author        = "liquid600pgm"
description   = "PNG animation library, made for motion graphics."
license       = "MIT"
srcDir        = "src"
bin           = @["pan/pan"]



# Dependencies

requires "nim >= 1.2.0"
requires "cairo#head"
requires "rapid#head"
requires "rdgui#head"
requires "https://github.com/liquid600pgm/nimLUA"
