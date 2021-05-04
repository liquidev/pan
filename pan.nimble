# Package

version       = "0.2.0"
author        = "lqdev"
description   = "puny animator – create motion graphics using Lua"
license       = "MIT"
srcDir        = "src"
bin           = @["pan"]
installExt    = @["nim"]

# Dependencies

requires "nim >= 1.4.2"
requires "cairo >= 1.1.1"
requires "rapid#21c847e"
requires "https://github.com/liquidev/nimLUA >= 0.3.8"
requires "stbimage >= 2.5"
requires "weave#5034793"  # mratsim please make a new release this makes me
                          # uncomfortable
