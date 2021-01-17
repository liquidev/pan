import std/macros
import std/options
import std/streams

import nimLUA

import api
import res

type
  ScriptEngine* = object
    anim*: Animation
    state*: PState
    scriptMain: string
    errors*: Option[string]
    pcallErrorHandlerIndex: cint
  LuaNil = object  ## dummy used to distinguish the Lua nil type

  StringReaderState = object
    str: cstring
    sentToLua: bool
  FileReaderState = object
    stream: FileStream
    buffer: array[1024, char]

const luaNil* = LuaNil()

proc getError(lua: PState): string =
  ## Gets the error result from pcall.
  let error = lua.toString(-1)
  lua.pop(1)
  result = error

proc pcallErrorHandler(lua: PState): cint {.cdecl.} =
  ## The error handler for pcall. This creates a stack traceback.
  let error = lua.toString(-1)
  lua.pop(1)
  lua.traceback(lua, error, 1)
  result = 1

proc stringReader(lua: PState, data: pointer,
                  size: var csize_t): cstring {.cdecl.} =
  ## Lua load() string reader.
  var state = cast[ptr StringReaderState](data)
  if not state.sentToLua:
    size = state.str.len.csize_t
    result = cast[cstring](state.str[0].unsafeAddr)
    state.sentToLua = true
  else:
    size = 0
    result = nil

proc fileReader(lua: PState, data: pointer,
                size: var csize_t): cstring {.cdecl.} =
  ## Lua load() file reader.
  var state = cast[ptr FileReaderState](data)
  if state.stream.atEnd:
    size = 0
    return nil
  size = state.stream.readData(addr state.buffer, sizeof(state.buffer)).csize_t
  result = addr state.buffer

proc loadFile(se: ScriptEngine, filename: string): Option[string] =
  ## Loads a file using the file reader mentioned above.
  var state = FileReaderState(stream: openFileStream(filename, fmRead))
  if se.state.load(fileReader, addr state, '@' & filename, "bt") != LUA_OK:
    result = some(se.state.getError())

proc loadString(se: ScriptEngine, filename, str: string): Option[string] =
  ## Loads a string using the string reader mentioned above.
  var state: StringReaderState
  state.str = cast[cstring](alloc((str.len + 1) * sizeof(char)))
  copyMem(state.str, str[0].unsafeAddr, (str.len + 1) * sizeof(char))
  if se.state.load(stringReader, addr state, '@' & filename, "bt") != LUA_OK:
    result = some(se.state.getError())
  dealloc(state.str)

proc call*(se: ScriptEngine, argCount, resultCount: int): Option[string] =
  ## Calls the function at the top of the stack using the script engine's pcall
  ## error handler for nice stack traces. Returns ``some`` if an error
  ## occured while running the function.
  let errCode = se.state.pcall(argCount.cint, resultCount.cint,
                               se.pcallErrorHandlerIndex)
  if errCode != LUA_OK:
    result = some(se.state.getError())

proc runFile*(se: ScriptEngine, filename: string): Option[string] =
  ## Loads and executes a file in the script engine. Returns ``some`` if an
  ## error occured while executing the file.
  let err = se.loadFile(filename)
  if err.isSome: return err
  result = se.call(0, 0)

proc runString*(se: ScriptEngine, filename, str: string): Option[string] =
  ## Loads and executes a script from a string. This additionally accepts a
  ## filename for use in stack tracebacks. Returns ``some`` if an error occured
  ## while executing the string.
  let err = se.loadString(filename, str)
  if err.isSome: return err
  result = se.call(0, 0)

proc error*(se: var ScriptEngine, message: string) =
  ## Sets se.error to the given error message.
  if se.errors.isNone:
    se.errors = some(message)
  else:
    se.errors.get.add('\n' & message)

proc reload*(se: var ScriptEngine) =
  ## Reloads the scripting engine's main string. This is used for hot reloading
  ## in preview mode. If an error occured, ``se.error`` is set to the error
  ## message.
  se.errors = string.none
  let error = se.runFile(se.scriptMain)
  if error.isSome:
    se.error("error in luafile:\n" & error.get)

macro genGlueProcs(): untyped =
  ## Generates glue procedures for binding in ``initScriptEngine``.
  result = newStmtList()
  for procedure in cgLuaProcs:
    var wrapper = newProc(name = ident($procedure.name & "_l"))
    wrapper.params[0] = procedure.params[0]
    for defs in procedure.params[2..^1]:
      var newDefs = newNimNode(nnkIdentDefs)
      for name in defs[0..^3]:
        newDefs.add(ident($name))
      newDefs.add(defs[^2..^1])
      wrapper.params.add(newDefs)
    wrapper.body = newStmtList()
    wrapper.addPragma(ident"cdecl")
    var call = newCall(procedure.name, bindSym"gAnim")
    for identDefs in wrapper.params[1..^1]:
      for name in identDefs[0..^3]:
        call.add(name)
    wrapper.body.add(call)
    result.add(wrapper)

proc namespaceSet*[T](lua: PState, tableIndex: int, key: string, val: T) =
  ## Sets a variable in tableIndex *and* the global namespace.
  discard lua.pushstring(key)
  for _ in 1..2:
    when T is LuaNil:
      lua.pushnil()
    elif T is SomeNumber:
      lua.pushnumber(val.float)
    else:
      # feel free to extend this if needed, this implementation only covers
      # what's used.
      {.error: "namespaceSet not available for " & $T.}
  lua.setglobal(key)
  lua.rawset(tableIndex.cint)

proc init*(se: var ScriptEngine, anim: Animation, scriptMain: string) =
  ## Initializes the scripting engine for the given animation and loads the
  ## given script.
  se.anim = anim
  se.scriptMain = scriptMain

  genGlueProcs()

  var lua = newNimLua()
  lua.openlibs()

  lua.pushcfunction(pcallErrorHandler)
  se.pcallErrorHandlerIndex = lua.gettop()

  lua.bindEnum:
    PanLineCap
    PanLineJoin
    PanFontWeight
    PanFontSlant
    PanTextHAlign
    PanTextVAlign
    PanAntialiasing
    PanBlendMode
    PanExtend
    PanFilter

  lua.bindObject(Color):
    initColor -> "_create"  # defer for rgba(), rgb(), gray()
    r(get, set) -> "raw_r"
    g(get, set) -> "raw_g"
    b(get, set) -> "raw_b"
    a(get, set) -> "raw_a"

  lua.bindObject(Image):
    newImage -> "_empty"  # defer for image.empty()
    loadImage -> "_load"  # defer for image.load()
    width(get)
    height(get)
    ~destroy

  lua.bindObject(Paint):
    solid -> "_createSolid"  # defer for solid()
    pattern -> "_createPattern"  # defer for pattern()
    withLineWidth -> "lineWidth"
    withLineCap -> "lineCap"
    withLineJoin -> "lineJoin"
    withAntialiasing -> "antialiasing"
    withBlendMode -> "blendMode"
    withExtend -> "extend"
    withFilter -> "filter"
    withMatrix -> "matrix"
    ~destroy

  lua.bindObject(Font):
    newFont -> "_create"  # defer for font()

  lua.bindObject(Matrix):
    matrixInvert -> "_invert"

  lua.bindProc("pan"):
    init_l -> "_init"
    clear_l -> "clear"
    push_l -> "push"
    pop_l -> "pop"
    pushPath_l -> "pushPath"
    popPath_l -> "popPath"
    begin_l -> "begin"
    moveTo_l -> "moveTo"
    moveBy_l -> "moveBy"
    lineTo_l -> "lineTo"
    relLineTo_l -> "relLineTo"
    rect_l -> "rect"
    arc_l -> "arc"
    close_l -> "close"
    fill_l -> "fill"
    stroke_l -> "stroke"
    clip_l -> "clip"
    switch_l -> "_switch"
    textSize_l -> "_textSize"
    text_l -> "_text"
    addText_l -> "addText"
    translate_l -> "translate"
    scale_l -> "scale"
    rotate_l -> "rotate"
    matrix_l -> "matrix"
    pathCursor_l -> "_pathCursor"

  se.state = lua

  const luapan = slurp("assets/pan.lua")
  let error = se.runString("<luapan>", luapan)
  if error.isSome:
    quit("error in luapan:\n" & error.get &
         "\nplease report an issue on github", -1)

proc renderFrame*(se: var ScriptEngine) =
  ## Renders a frame of animation at the time set in the scripting engine's
  ## animation. Sets ``se.errors`` if an error occurs during ``render()``.
  se.state.getglobal("pan")
  let panIndex = se.state.gettop()

  se.state.getglobal("render")
  if not se.state.isfunction(-1):
    se.state.pop(1)
    se.error("error in luafile: no render() function")
    se.state.pop(1)
    return

  se.state.namespaceSet(panIndex, "time", se.anim.time)
  let error = se.call(0, 0)
  if error.isSome:
    se.error("error in luafile (in render()):\n" & error.get)
  se.state.namespaceSet(panIndex, "time", luaNil)

  se.state.pop(1)
