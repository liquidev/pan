-- luapan - pan's standard library
-- copyright (C) iLiquid, 2020

do

  -- PROJECT

  local animationImpl = pan__animationImpl
  pan__animationImpl = nil

  function animation(opt)
    if opt.width == nil then error("missing frame width") end
    if opt.height == nil then error("missing frame height") end
    if opt.length == nil then error("missing animation length") end
    if opt.framerate == nil then opt.framerate = 60 end
    if opt.width <= 0 or opt.height <= 0 then
      error("width and height must be positive")
    end
    animationImpl(opt.width, opt.height, opt.length, opt.framerate)
  end

  -- COLOR

  local rgbaImpl = Color._createRgbaImpl
  local fontImpl = Font._createImpl

  rgba = rgbaImpl
  solid = Paint._createSolidImpl

  Color._createRgbaImpl = nil
  Font._createImpl = nil
  Paint._createSolidImpl = nil

  function rgb(r, g, b)
    return rgbaImpl(r, g, b, 255)
  end

  function gray(value, alpha)
    if alpha == nil then alpha = 255 end
    return rgbaImpl(value, value, value, alpha)
  end

  function hex(hexcode)
    local h = hexcode
    if #h > 0 and h:sub(1, 1) == '#' then
      h = h:sub(2)
    end

    local r, g, b, a = 0, 0, 0, 255

    if #h == 3 and #h == 4 then
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

    return rgbaImpl(r, g, b, a)
  end


  -- DRAWING

  function line(x0, y0, x1, y1, paint)
    begin()
    moveTo(x0, y0)
    lineTo(x1, y1)
    stroke(paint)
  end

  function rects(x, y, w, h, paint)
    begin()
    rect(x, y, w, h)
    stroke(paint)
  end

  function rectf(x, y, w, h, paint)
    begin()
    rect(x, y, w, h)
    fill(paint)
  end

  function circles(x, y, r, paint)
    begin()
    arc(x, y, r, 0, math.pi * 2)
    stroke(paint)
  end

  function circlef(x, y, r, paint)
    begin()
    arc(x, y, r, 0, math.pi * 2)
    fill(paint)
  end

  function cliprect(x, y, w, h)
    begin()
    rect(x, y, w, h)
    clip()
  end

  function font(name, weight, slant)
    if weight == nil then weight = fwNormal end
    if slant == nil then slant = fsNone end
    return fontImpl(name, weight, slant)
  end

  local textImpl = pan__textImpl
  pan__textImpl = nil

  function text(font, x, y, _text, size, w, h, halign, valign)
    if w == nil then w = 0 end
    if h == nil then h = 0 end
    if halign == nil then halign = taLeft end
    if valign == nil then valign = taTop end
    textImpl(font, x, y, _text, size, w, h, halign, valign)
  end

  function textf(font, x, y, text_, size, paint, w, h, halign, valign)
    begin()
    text(font, x, y, text_, size, w, h, halign, valign)
    fill(paint)
  end

  function texts(font, x, y, text_, size, paint, w, h, halign, valign)
    begin()
    text(font, x, y, text_, size, w, h, halign, valign)
    stroke(paint)
  end

  -- MATH

  function clamp(x, a, b)
    return math.min(math.max(x, a), b)
  end

  -- ANIMATION

  function linear(x)
    return x
  end

  function step(x)
    if x < 0.9999 then return 0
    else return 1
    end
  end

  function interp(a, b, t, func)
    if func == nil then func = linear end
    t = func(clamp(t, 0, 1))
    return (1 - t) * a + t * b
  end

  function ease(a, b, starttime, endtime, func)
    local t = (time - starttime) / (endtime - starttime)
    return interp(a, b, t, func)
  end

  function easel(a, b, starttime, length, func)
    return ease(a, b, starttime, starttime + length, func)
  end

  function keyframes(k)
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
    for i, iv in ipairs(intervals) do
      if time > iv.tfrom and time < iv.tto then
        return ease(iv.vfrom, iv.vto, iv.tfrom, iv.tto, iv.easing)
      elseif time > iv.tto then
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

    function sineIn(x) return 1 - math.cos((x * math.pi) / 2) end
    function sineOut(x) return math.sin((x * math.pi) / 2) end
    function sineInOut(x) return -(math.cos(math.pi * x) - 1) / 2 end

    function quadIn(x) return x * x end
    quadOut = inv(quadIn)
    function quadInOut(x)
      if x < 0.5 then return 2 * x * x
      else return 1 - (-2 * x + 2)^2 / 2
      end
    end

    function cubicIn(x) return x * x * x end
    cubicOut = inv(cubicIn)
    function cubicInOut(x)
      if x < 0.5 then return 4 * x * x * x
      else return 1 - (-2 * x + 2)^3 / 2
      end
    end

    function quarticIn(x) return x * x * x * x end
    quarticOut = inv(quarticIn)
    function quarticInOut(x)
      if x < 0.5 then return 8 * x * x * x * x
      else return 1 - (-2 * x + 2)^4 / 2
      end
    end

    function quinticIn(x) return x * x * x * x * x end
    quinticOut = inv(quinticIn)
    function quinticInOut(x)
      if x < 0.5 then return 16 * x * x * x * x * x
      else return 1 - (-2 * x + 2)^5 / 2
      end
    end

    function expoIn(x)
      if x == 0 then return 0
      else return 2^(10 * x - 10)
      end
    end
    expoOut = inv(expoIn)
    function expoInOut(x)
      if x == 0 then return 0
      elseif x == 1 then return 1
      else
        if x < 0.5 then return 2^(20 * x - 10) / 2
        else return (2 - 2^(-20 * x + 10)) / 2
        end
      end
    end

    function circIn(x)
      return 1 - math.sqrt(1 - x * x)
    end
    circOut = inv(circIn)
    function circInOut(x)
      if x < 0.5 then return (1 - math.sqrt(1 - (2 * x)^2)) / 2
      else return (math.sqrt(1 - (-2 * x + 2)^2) + 1) / 2
      end
    end

    function backOut(x)
      local c1 = 1.70158;
      local c3 = c1 + 1;

      return 1 + c3 * (x - 1)^3 + c1 * (x - 1)^2;
    end
    backIn = inv(backOut)
    function backInOut(x)
      local c1 = 1.70158;
      local c2 = c1 * 1.525;

      if x < 0.5 then return ((2 * x)^2 * ((c2 + 1) * 2 * x - c2)) / 2
      else return ((2 * x - 2)^2 * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2;
      end
    end

    function elasticIn(x)
      local c4 = (2 * math.pi) / 3;

      if x == 0 then return 0
      elseif x == 1 then return 1
      else return -2^(10 * x - 10) * math.sin((x * 10 - 10.75) * c4)
      end
    end
    elasticOut = inv(elasticIn)
    function elasticInOut(x)
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

    function bounceOut(x)
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
    bounceIn = inv(bounceOut)
    function bounceInOut(x)
      if x < 0.5 then return (1 - bounceOut(1 - 2 * x)) / 2
      else return (1 + bounceOut(2 * x - 1)) / 2
      end
    end


    Easings = {
      linear = linear,
      step = step,
      In = {
        sine = sineIn,
        quad = quadIn,
        cubic = cubicIn,
        quartic = quarticIn,
        quintic = quinticIn,
        expo = expoIn,
        circ = circIn,
        back = backIn,
        elastic = elasticIn,
        bounce = bounceIn,
      },
      Out = {
        sine = sineOut,
        quad = quadOut,
        cubic = cubicOut,
        quartic = quarticOut,
        quintic = quinticOut,
        expo = expoOut,
        circ = circOut,
        back = backOut,
        elastic = elasticOut,
        bounce = bounceOut,
      },
      InOut = {
        sine = sineInOut,
        quad = quadInOut,
        cubic = cubicInOut,
        quartic = quarticInOut,
        quintic = quinticInOut,
        expo = expoInOut,
        circ = circInOut,
        back = backInOut,
        elastic = elasticInOut,
        bounce = bounceInOut,
      },
    }
  end

  -- EXTRA

  function len(x)
    if type(x) == "string" then
      return #x
    elseif type(x) == "table" then
      local count = 0
      for _, _ in pairs(x) do
        count = count + 1
      end
      return count
    else
      return 0
    end
  end

  function repr(x)
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
        local indent = string.rep(' ', level)
        local indented = {}
        for _, line in pairs(lines) do
          table.insert(indented, indent..line..'\n')
        end
        return table.concat(indented)
      end
      for k, v in pairs(x) do
        table.insert(result, indent(k.." = "..repr(v)..", \n", 2))
      end
      return "{\n"..table.concat(result).."}"
    else
      return tostring(x)
    end
  end

end
