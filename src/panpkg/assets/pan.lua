-- luapan - pan's standard library
-- copyright (C) lqdev, 2020-2021


-- enums

do
  local enums = {
    "PanLineCap",
    "PanLineJoin",
    "PanFontWeight",
    "PanFontSlant",
    "PanTextHAlign",
    "PanTextVAlign",
    "PanAntialiasing",
    "PanBlendMode",
    "PanExtend",
    "PanFilter",
  }

  for _, typename in ipairs(enums) do
    local enum = _G[typename]
    _G[typename] = nil
    for name, value in pairs(enum) do
      pan[name] = value
    end
  end
end


-- PROJECT

local implInit = pan._init
pan._init = nil

function pan.animation(opt)
  assert(type(opt.width) == "number", "frame width must be a number")
  assert(type(opt.height) == "number", "frame height must be a number")
  assert(type(opt.length) == "number", "animation length must be a number")
  opt.framerate = opt.framerate or 60
  assert(type(opt.framerate) == "number", "framerate must be a number")
  assert(opt.width > 0 and opt.height > 0, "frame size must be positive")
  assert(opt.length > 0, "animation length must be positive")
  assert(opt.framerate > 0, "animation framerate must be positive")

  -- wanted to do this from Nim, but sadly closures are notc compatible with
  -- cdecl which is what nimLUA expects. thus, i could not close over the
  -- lua state in order to do these rawsets. oh well.
  rawset(pan, "width", opt.width)
  rawset(pan, "height", opt.height)
  rawset(pan, "length", opt.length)
  rawset(pan, "framerate", opt.framerate)
  width = pan.width
  height = pan.height
  length = pan.length
  framerate = pan.framerate

  implInit(opt.width, opt.height, opt.length, opt.framerate)
end


-- COLOR

local implRgba = Color._create
local implFont = Font._create

pan.solid = Paint._createSolid
pan.pattern = Paint._createPattern

Color._create = nil
Font._create = nil
Paint._createSolid = nil
Paint._createPattern = nil

local colorIndex = Color.__index
function Color.__index(self, key)
  if     key == 'r' then return self.raw_r * 255
  elseif key == 'g' then return self.raw_g * 255
  elseif key == 'b' then return self.raw_b * 255
  elseif key == 'a' then return self.raw_a * 255
  end
  return colorIndex(self, key)
end

function pan.rgba(r, g, b, a)
  return implRgba(r / 255, g / 255, b / 255, a / 255)
end

function pan.rgb(r, g, b)
  return pan.rgba(r, g, b, 255)
end

function pan.gray(value, alpha)
  if alpha == nil then alpha = 255 end
  return pan.rgba(value, value, value, alpha)
end

function pan.hex(hexcode)
  local h = hexcode
  if #h > 0 and h:sub(1, 1) == '#' then
    h = h:sub(2)
  end

  local r, g, b, a = 0, 0, 0, 255

  if #h == 3 or #h == 4 then
    r = tonumber(h:sub(1, 1), 16)
    g = tonumber(h:sub(2, 2), 16)
    b = tonumber(h:sub(3, 3), 16)
    if #h == 4 then
      a = tonumber(h:sub(4, 4), 16)
    end
  elseif #h == 6 or #h == 8 then
    r = tonumber(h:sub(1, 2), 16)
    g = tonumber(h:sub(3, 4), 16)
    b = tonumber(h:sub(5, 6), 16)
    if #h == 8 then
      a = tonumber(h:sub(7, 8), 16)
    end
  else
    error("invalid hex code: '"..hexcode.."'")
  end

  return pan.rgba(r, g, b, a)
end

function Color.withRed(self, r)
  return pan.rgba(r, self.g, self.b, self.a)
end

function Color.withGreen(self, g)
  return pan.rgba(self.r, g, self.b, self.a)
end

function Color.withBlue(self, b)
  return pan.rgba(self.r, self.g, b, self.a)
end

function Color.withAlpha(self, a)
  return pan.rgba(self.r, self.g, self.b, a)
end

function Color.mulAlpha(self, coeff)
  return self:withAlpha(self.a * coeff)
end


-- IMAGES

pan.image = {
  empty = Image._empty,
  load = Image._load,
  result = pan._switch(),
}
Image._empty = nil
Image._load = nil

function Image.size(self)
  return self.width, self.height
end


-- DRAWING

local implPathCursor = pan._pathCursor
pan._pathCursor = nil

function pan.pathCursor()
  local pos = implPathCursor()
  return pos.x, pos.y
end

function pan.line(x0, y0, x1, y1, paint)
  pan.pushPath()
  pan.begin()
  pan.moveTo(x0, y0)
  pan.lineTo(x1, y1)
  pan.stroke(paint)
  pan.popPath()
end

function pan.rects(x, y, w, h, paint)
  pan.pushPath()
  pan.begin()
  pan.rect(x, y, w, h)
  pan.stroke(paint)
  pan.popPath()
end

function pan.rectf(x, y, w, h, paint)
  pan.pushPath()
  pan.begin()
  pan.rect(x, y, w, h)
  pan.fill(paint)
  pan.popPath()
end

function pan.circles(x, y, r, paint)
  pan.pushPath()
  pan.begin()
  pan.arc(x, y, r, 0, math.pi * 2)
  pan.stroke(paint)
  pan.popPath()
end

function pan.circlef(x, y, r, paint)
  pan.pushPath()
  pan.begin()
  pan.arc(x, y, r, 0, math.pi * 2)
  pan.fill(paint)
  pan.popPath()
end

function pan.cliprect(x, y, w, h)
  pan.pushPath()
  pan.begin()
  pan.rect(x, y, w, h)
  pan.clip()
  pan.popPath()
end

function pan.blit(image, x, y, w, h, t)
  assert(type(image) == "userdata", "image must be provided")
  assert(type(x) == "number" and type(y) == "number",
    "blit position must be provided")

  if type(w) == "number" then
    assert(type(h) == "number", "both width and height must be provided")
  else
    w, h = image:size()
  end

  t = t or {}

  pan.push()
  pan.cliprect(x, y, w, h)

  pan.scale(w / image.width, h / image.height)
  pan.translate(x, y)

  pan.clear(pan.pattern(image) -- a bit inefficient wrt allocations
    :filter(t.filter or Nearest))

  pan.pop()
end

local switchImpl = pan._switch
pan._switch = nil
function pan.switch(dest)
  local result = switchImpl(dest)
  if dest ~= nil then
    rawset(pan, "width", dest.width)
    rawset(pan, "height", dest.height)
    width = dest.width
    height = dest.height
  end
  return result
end

function pan.font(name, weight, slant)
  weight = weight or fwNormal
  slant = slant or fsNone
  return implFont(name, weight, slant)
end

local implText = pan._text
local implTextSize = pan._textSize
pan._text = nil
pan._textSize = nil

function pan.text(font, x, y, text_, size, w, h, halign, valign)
  if w == nil then w = 0 end
  if h == nil then h = 0 end
  if halign == nil then halign = taLeft end
  if valign == nil then valign = taTop end
  implText(font, x, y, text_, size, w, h, halign, valign)
end

function pan.textf(font, x, y, text_, size, paint, w, h, halign, valign)
  pan.pushPath()
  pan.begin()
  pan.text(font, x, y, text_, size, w, h, halign, valign)
  pan.fill(paint)
  pan.popPath()
end

function pan.texts(font, x, y, text_, size, paint, w, h, halign, valign)
  pan.pushPath()
  pan.begin()
  pan.text(font, x, y, text_, size, w, h, halign, valign)
  pan.stroke(paint)
  pan.popPath()
end

local spaceWidths = setmetatable({}, { __mode = 'k' })

local function rawTextSize(font, text, size)
  local s = implTextSize(font, text, size)
  return s.w, s.h
end

-- workaround for cairo not including trailing spaces in its text extents.
-- i am aware that this is a bit imprecise because of kerning, but should be
-- good enough for most basic purposes
local function getSpaceWidth(font, size)
  if not spaceWidths[font] then
    spaceWidths[font] = {}
  end

  local width = spaceWidths[font][size]
  if not width then
    local spacew = rawTextSize(font, " w", size)
    local w = rawTextSize(font, 'w', size)
    width = spacew - w
    spaceWidths[font][size] = width
  end
  return width
end

function pan.textSize(font, text, size)
  if #text == 0 then return 0, 0 end

  local w, h = rawTextSize(font, text, size)

  -- lua please give us proper string indexing kthx
  local start, fin = text:find("%s+$")
  if start then
    local count = fin - start + 1
    local space = getSpaceWidth(font, size)
    w = w + count * space
  end

  return w, h
end


-- MATH

function pan.clamp(x, a, b)
  return math.min(math.max(x, a), b)
end

function pan.map(x, min0, max0, min1, max1)
  return min1 + ((x - min0) / (max0 - min0)) * (max1 - min1)
end

local matrixInvertImpl = Matrix._invert
Matrix._invert = nil

function Matrix.invert(self)
  local r = matrixInvertImpl(self)
  if r.ok then
    return r.m
  else
    return nil
  end
end


-- ANIMATION

function pan.warpTime(amount, callback)
  if pan.time == nil then
    error("warpTime() can only be called in render()")
  end
  local oldTime = pan.time
  rawset(pan, "time", oldTime - amount)
  callback()
  rawset(pan, "time", oldTime)
end

function pan.linear(x)
  return x
end

function pan.step(x)
  if x < 0.9999 then return 0
  else return 1
  end
end

function pan.interp(a, b, t, func)
  if func == nil then func = linear end
  t = func(clamp(t, 0, 1))
  return (1 - t) * a + t * b
end

function pan.ease(a, b, starttime, endtime, func)
  local t = (pan.time - starttime) / (endtime - starttime)
  return pan.interp(a, b, t, func)
end

function pan.easel(a, b, starttime, length, func)
  return pan.ease(a, b, starttime, starttime + length, func)
end

function pan.keyframes(k)
  if #k < 1 then error("at least 1 keyframe must be provided") end

  local intervals = {}

  local function validatekey(i, key)
    if key.time == nil then error("key "..i..": no time provided") end
    if key.val == nil then error("key "..i..": no value provided") end
    if key.easing == nil then key.easing = linear end
  end

  do
    validatekey(1, k[1])
    local lasttime, lastval = k[1].time, k[1].val
    for i = 2, #k do
      validatekey(i, k[i])
      table.insert(intervals, {
        tfrom = lasttime, tto = k[i].time,
        vfrom = lastval, vto = k[i].val,
        easing = k[i].easing,
      })
      lasttime, lastval = k[i].time, k[i].val
    end
  end

  local fallback = intervals[1].vfrom
  for _, iv in ipairs(intervals) do
    if pan.time > iv.tfrom and pan.time < iv.tto then
      return pan.ease(iv.vfrom, iv.vto, iv.tfrom, iv.tto, iv.easing)
    elseif pan.time >= iv.tto then
      fallback = iv.vto
    end
  end
  return fallback
end

do

  -- easing functions ported from
  -- https://easings.net

  local function inv(f)
    return function (x) return 1 - f(1 - x) end
  end

  function pan.sineIn(x) return 1 - math.cos((x * math.pi) / 2) end
  function pan.sineOut(x) return math.sin((x * math.pi) / 2) end
  function pan.sineInOut(x) return -(math.cos(math.pi * x) - 1) / 2 end

  function pan.quadIn(x) return x * x end
  pan.quadOut = inv(pan.quadIn)
  function pan.quadInOut(x)
    if x < 0.5 then return 2 * x * x
    else return 1 - (-2 * x + 2)^2 / 2
    end
  end

  function pan.cubicIn(x) return x * x * x end
  pan.cubicOut = inv(pan.cubicIn)
  function pan.cubicInOut(x)
    if x < 0.5 then return 4 * x * x * x
    else return 1 - (-2 * x + 2)^3 / 2
    end
  end

  function pan.quarticIn(x) return x * x * x * x end
  pan.quarticOut = inv(pan.quarticIn)
  function pan.quarticInOut(x)
    if x < 0.5 then return 8 * x * x * x * x
    else return 1 - (-2 * x + 2)^4 / 2
    end
  end

  function pan.quinticIn(x) return x * x * x * x * x end
  pan.quinticOut = inv(pan.quinticIn)
  function pan.quinticInOut(x)
    if x < 0.5 then return 16 * x * x * x * x * x
    else return 1 - (-2 * x + 2)^5 / 2
    end
  end

  function pan.expoIn(x)
    if x == 0 then return 0
    else return 2^(10 * x - 10)
    end
  end
  pan.expoOut = inv(pan.expoIn)
  function pan.expoInOut(x)
    if x == 0 then return 0
    elseif x == 1 then return 1
    else
      if x < 0.5 then return 2^(20 * x - 10) / 2
      else return (2 - 2^(-20 * x + 10)) / 2
      end
    end
  end

  function pan.circIn(x)
    return 1 - math.sqrt(1 - x * x)
  end
  pan.circOut = inv(pan.circIn)
  function pan.circInOut(x)
    if x < 0.5 then return (1 - math.sqrt(1 - (2 * x)^2)) / 2
    else return (math.sqrt(1 - (-2 * x + 2)^2) + 1) / 2
    end
  end

  function pan.backOut(x)
    local c1 = 1.70158;
    local c3 = c1 + 1;

    return 1 + c3 * (x - 1)^3 + c1 * (x - 1)^2;
  end
  pan.backIn = inv(pan.backOut)
  function pan.backInOut(x)
    local c1 = 1.70158;
    local c2 = c1 * 1.525;

    if x < 0.5 then return ((2 * x)^2 * ((c2 + 1) * 2 * x - c2)) / 2
    else return ((2 * x - 2)^2 * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2;
    end
  end

  function pan.elasticIn(x)
    local c4 = (2 * math.pi) / 3;

    if x == 0 then return 0
    elseif x == 1 then return 1
    else return -2^(10 * x - 10) * math.sin((x * 10 - 10.75) * c4)
    end
  end
  pan.elasticOut = inv(pan.elasticIn)
  function pan.elasticInOut(x)
    local c5 = (2 * math.pi) / 4.5;

    if x == 0 then return 0
    elseif x == 1 then return 1
    else
      if x < 0.5 then
        return -(2^(20 * x - 10) * math.sin((20 * x - 11.125) * c5)) / 2
      else
        return (2^(-20 * x + 10) * math.sin((20 * x - 11.125) * c5)) / 2 + 1
      end
    end
  end

  function pan.bounceOut(x)
    local n1 = 7.5625
    local d1 = 2.75

    if x < 1 / d1 then
      return n1 * x * x
    elseif x < 2 / d1 then
      x = x - 1.5 / d1
      return n1 * x * x + 0.75
    elseif x < 2.5 / d1 then
      x = x - 2.25 / d1
      return n1 * x * x + 0.9375
    else
      x = x - 2.625 / d1
      return n1 * x * x + 0.984375
    end
  end
  pan.bounceIn = inv(pan.bounceOut)
  function pan.bounceInOut(x)
    if x < 0.5 then return (1 - pan.bounceOut(1 - 2 * x)) / 2
    else return (1 + pan.bounceOut(2 * x - 1)) / 2
    end
  end


  pan.Easings = {
    linear = pan.linear,
    step = pan.step,
    In = {
      sine = pan.sineIn,
      quad = pan.quadIn,
      cubic = pan.cubicIn,
      quartic = pan.quarticIn,
      quintic = pan.quinticIn,
      expo = pan.expoIn,
      circ = pan.circIn,
      back = pan.backIn,
      elastic = pan.elasticIn,
      bounce = pan.bounceIn,
    },
    Out = {
      sine = pan.sineOut,
      quad = pan.quadOut,
      cubic = pan.cubicOut,
      quartic = pan.quarticOut,
      quintic = pan.quinticOut,
      expo = pan.expoOut,
      circ = pan.circOut,
      back = pan.backOut,
      elastic = pan.elasticOut,
      bounce = pan.bounceOut,
    },
    InOut = {
      sine = pan.sineInOut,
      quad = pan.quadInOut,
      cubic = pan.cubicInOut,
      quartic = pan.quarticInOut,
      quintic = pan.quinticInOut,
      expo = pan.expoInOut,
      circ = pan.circInOut,
      back = pan.backInOut,
      elastic = pan.elasticInOut,
      bounce = pan.bounceInOut,
    },
  }
end


-- EXTRA

function pan.len(x)
  if type(x) == "string" then
    return #x
  elseif type(x) == "table" then
    local count = 0
    for _, _ in pairs(x) do
      count = count + 1
    end
    return count
  else
    if getmetatable(x).__len ~= nil then
      return #x
    else
      return 0
    end
  end
end

function pan.repr(x)
  if type(x) == "table" then
    local result = {}
    local function indent(s, level)
      local lines = {}
      local buffer = {}
      for i = 1, #s do
        if s:sub(i, i) == '\n' then
          table.insert(lines, table.concat(buffer))
          buffer = {}
        else
          table.insert(buffer, s:sub(i, i))
        end
      end
      if #buffer > 0 then
        table.insert(lines, table.concat(buffer))
      end
      local spaces = string.rep(' ', level)
      local indented = {}
      for _, line in pairs(lines) do
        table.insert(indented, spaces..line..'\n')
      end
      return table.concat(indented)
    end
    for k, v in pairs(x) do
      table.insert(result, indent(k.." = "..pan.repr(v)..", \n", 2))
    end
    return "{\n"..table.concat(result).."}"
  else
    return tostring(x)
  end
end

local pkgLoaded = package.loaded
local pkgRequire = require
function pan.require(modname)
  local module = pkgRequire(modname)
  pkgLoaded[modname] = false
  return module
end

-- lock the pan namespace from outside modifications
setmetatable(pan, {
  __newindex = function ()
    error("the pan namespace is immutable")
  end
})

-- copy all keys from the pan namespace to _G
-- this effectively makes all pan functions accessible from the global
-- namespace, but in case they're overwritten, they're still available from
-- the pan namespace which is immutable
for key, val in pairs(pan) do
  -- we only override functions that are not in the global namespace already,
  -- so `require` (and maybe other functions in the future) are ignored
  if _G[key] == nil then
    _G[key] = val
  end
end
