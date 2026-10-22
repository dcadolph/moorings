-- banner draws the moorings banner, a box at the top right of the primary screen that
-- says what moorings did. It stands in for macOS notifications, which always show as
-- Hammerspoon and need their own permission.

local B = {}

-- seconds is how long a banner stays up after it opens or the pointer leaves it.
B.seconds = 5

-- fadeSeconds is how long a banner takes to fade away.
B.fadeSeconds = 0.4

-- markPath is the full path of the banner mark, a black SVG. Nil draws no mark.
B.markPath = nil

-- width, margin and wrapAt shape the box: its width, its distance from the screen's top
-- right corner, and the most characters a body line holds before it wraps.
local width, margin, wrapAt = 380, { x = 14, y = 10 }, 46

-- styles holds the box, stroke and text colors for light and dark mode.
local styles = {
  light = {
    fill = { white = 0.98, alpha = 0.97 },
    stroke = { white = 0, alpha = 0.12 },
    text = { white = 0 },
    body = { white = 0, alpha = 0.75 },
  },
  dark = {
    fill = { red = 0.16, green = 0.16, blue = 0.17, alpha = 0.96 },
    stroke = { white = 1, alpha = 0.12 },
    text = { white = 1 },
    body = { white = 1, alpha = 0.75 },
  },
}

-- state holds the banner on screen and the marks loaded so far.
local state = {
  -- current is the banner on screen, or nil.
  current = nil,
  -- marks maps a style name to its loaded mark image, or false when it did not load.
  marks = {},
}

-- wrap splits text into lines of at most wrapAt characters at spaces, keeping its newlines.
-- A word longer than a line stays whole on a line of its own.
function B.wrap(text)
  local lines = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      if line == "" then
        line = word
      elseif utf8.len(line) + 1 + utf8.len(word) <= wrapAt then
        line = line .. " " .. word
      else
        lines[#lines + 1] = line
        line = word
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- style returns "dark" when macOS is in dark mode and "light" otherwise.
function B.style()
  return hs.host.interfaceStyle() == "Dark" and "dark" or "light"
end

-- mark returns the banner mark for style, white on dark and black on light, or nil when
-- it does not load. Dark swaps the SVG's black and white before loading it.
function B.mark(style)
  if state.marks[style] ~= nil then
    return state.marks[style] or nil
  end
  local img
  local f = B.markPath and io.open(B.markPath, "r")
  if f then
    local svg = f:read("a")
    f:close()
    if style == "dark" then
      svg = svg:gsub("#%x%x%x%f[^%x]", { ["#000"] = "#fff", ["#fff"] = "#000" })
    end
    img = hs.image.imageFromURL("data:image/svg+xml;base64," .. hs.base64.encode(svg))
  end
  state.marks[style] = img or false
  return img
end

-- frame returns the box for a banner with lines body lines on the primary screen.
function B.frame(lines)
  local f = hs.screen.primaryScreen():frame()
  local h = 42 + 16 * lines
  return { x = f.x + f.w - width - margin.x, y = f.y + margin.y, w = width, h = h }
end

-- close removes banner b, fading it when fade is true. It does nothing to a banner that
-- is already gone.
local function close(b, fade)
  if b.closed then
    return
  end
  b.closed = true
  if b.timer then
    b.timer:stop()
  end
  if fade then
    b.canvas:delete(B.fadeSeconds)
  else
    b.canvas:delete()
  end
  if state.current == b then
    state.current = nil
  end
end

-- arm starts banner b's countdown again, unless it is sticky.
local function arm(b)
  if b.timer then
    b.timer:stop()
    b.timer = nil
  end
  if not b.sticky then
    b.timer = hs.timer.doAfter(B.seconds, function() close(b, true) end)
  end
end

-- B.show draws a banner with opts.title and opts.text and replaces the one on screen.
-- Clicking it runs opts.click, when given, and closes it. Pointing at it holds it open.
-- An opts.sticky banner stays until clicked or withdrawn. It returns a handle whose
-- withdraw method closes the banner.
function B.show(opts)
  if state.current then
    close(state.current, false)
  end
  local style = B.style()
  local colors = styles[style]
  local lines = B.wrap(opts.text or "")
  local f = B.frame(#lines)
  local c = hs.canvas.new(f)
  c:appendElements(
    {
      type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 16, yRadius = 16 },
      fillColor = colors.fill, withShadow = true,
      shadow = { blurRadius = 12, color = { alpha = 0.45 }, offset = { h = -3, w = 0 } },
    },
    {
      type = "rectangle", action = "stroke", roundedRectRadii = { xRadius = 16, yRadius = 16 },
      strokeColor = colors.stroke, strokeWidth = 1,
    },
    {
      type = "text", frame = { x = 68, y = 16, w = width - 84, h = 20 },
      text = hs.styledtext.new(opts.title, {
        font = { name = ".AppleSystemUIFontBold", size = 13 }, color = colors.text,
      }),
    },
    {
      type = "text", frame = { x = 68, y = 36, w = width - 84, h = f.h - 40 },
      text = hs.styledtext.new(table.concat(lines, "\n"), {
        font = { name = ".AppleSystemUIFont", size = 12 }, color = colors.body,
      }),
    }
  )
  local img = B.mark(style)
  if img then
    c:appendElements({
      type = "image", image = img, imageScaling = "scaleProportionally",
      frame = { x = 16, y = (f.h - 40) / 2, w = 40, h = 40 },
    })
  end
  local b = { canvas = c, sticky = opts.sticky == true }
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:level("overlay")
  c:canvasMouseEvents(true, false, true, false)
  c:mouseCallback(function(_, msg)
    if b.closed then
      return
    end
    if msg == "mouseDown" then
      close(b, true)
      if opts.click then
        opts.click()
      end
    elseif msg == "mouseEnter" then
      if b.timer then
        b.timer:stop()
        b.timer = nil
      end
    elseif msg == "mouseExit" then
      arm(b)
    end
  end)
  c:show(0.2)
  state.current = b
  arm(b)
  return { withdraw = function() close(b, true) end }
end

return B
