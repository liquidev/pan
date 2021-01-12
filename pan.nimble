# Package

version       = "0.2.0"
author        = "lqdev"
description   = "PNG animation library, made for motion graphics."
license       = "MIT"
srcDir        = "src"
bin           = @["pan/pan"]



# Dependencies

requires "nim >= 1.4.2"
requires "cairo >= 1.1.1"
requires "rapid#head"
requires "https://github.com/liquidev/nimLUA >= 0.3.8"
