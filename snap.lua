-- snap places a window dragged to a screen edge, as Rectangle does. On the
-- ultrawide the edges belong to the pins, so the strips stand in for them and
-- every snap lands in the channel. A footprint shows the target while the
-- mouse is held.

local S = {}

-- margin is how close in points the cursor must come to an edge.
local margin = 5

-- corner is how far in points from a corner the quarter zones reach.
local corner = 20

-- short is how far in points from a corner the half zones on an edge reach.
local short = 145

-- maxChecks is how many drag events may pass before a window that has not
-- moved is taken for a click inside it, and snapping stops for that drag.
local maxChecks = 20

-- third returns the third under x across the span ox to ox+w. The center third
-- becomes two thirds when the drag came from a side third.
local function third(x, ox, w, prev)
  local i = math.max(0, math.min(2, math.floor((x - ox) * 3 / w)))
  if i == 0 then
    return "first-third"
  elseif i == 2 then
    return "last-third"
  elseif prev == "first-third" or prev == "first-two-thirds" then
    return "first-two-thirds"
  elseif prev == "last-third" or prev == "last-two-thirds" then
    return "last-two-thirds"
  end
  return "center-third"
end

-- zone returns the action a window dropped at point p gets on a display whose
-- full frame is f, or nil. ch is the channel when the display is the
-- ultrawide. prev is the zone the drag was last in.
function S.zone(p, f, ch, prev)
  local l, r = p.x - f.x, f.x + f.w - p.x
  local t, b = p.y - f.y, f.y + f.h - p.y
  local atTop, atBottom = t < margin, b <= margin
  if ch then
    local side = (p.x < ch.x and "left") or (p.x >= ch.x + ch.w and "right") or nil
    if side then
      if t < short then
        return "top-" .. side
      elseif b <= short then
        return "bottom-" .. side
      end
      return side .. "-half"
    end
    if atTop then
      return "maximize"
    elseif atBottom then
      return third(p.x, ch.x, ch.w, prev)
    end
    return nil
  end
  if l < margin or r <= margin then
    local side = l < margin and "left" or "right"
    if t < corner then
      return "top-" .. side
    elseif b <= corner then
      return "bottom-" .. side
    elseif t < short then
      return "top-half"
    elseif b <= short then
      return "bottom-half"
    end
    return side .. "-half"
  end
  if atTop or atBottom then
    local row = atTop and "top" or "bottom"
    if l < corner then
      return row .. "-left"
    elseif r <= corner then
      return row .. "-right"
    elseif l < short or r <= short then
      return row .. "-half"
    end
    return atTop and "maximize" or third(p.x, f.x, f.w, prev)
  end
  return nil
end

local host, actions
local state = {}

-- attach gives snap the anchors module and the action runner.
function S.attach(m, a)
  host, actions = m, a
end

-- hide removes the footprint.
local function hide()
  if state.canvas then
    state.canvas:delete()
    state.canvas = nil
  end
end

-- show draws the footprint at frame, reusing the canvas while a drag lasts.
local function show(frame)
  if state.canvas then
    state.canvas:frame(frame)
    return
  end
  state.canvas = hs.canvas.new(frame)
  state.canvas:appendElements({
    type = "rectangle",
    action = "strokeAndFill",
    fillColor = { white = 1, alpha = 0.18 },
    strokeColor = { white = 1, alpha = 0.6 },
    strokeWidth = 2,
    roundedRectRadii = { xRadius = 8, yRadius = 8 },
  })
  state.canvas:level("floating")
  state.canvas:show()
end

-- reset forgets the drag and removes the footprint.
local function reset()
  hide()
  state = {}
end

-- screenAt returns the screen whose full frame holds p, or nil.
local function screenAt(p)
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    if p.x >= f.x and p.x < f.x + f.w and p.y >= f.y and p.y < f.y + f.h then
      return s
    end
  end
  return nil
end

-- channelOf returns the channel of s when s is the ultrawide, or nil.
local function channelOf(s)
  local wide = host.ultrawide()
  if wide and wide:id() == s:id() then
    return host.channel(s)
  end
  return nil
end

-- moving reports whether the drag is moving a window, watching its frame until
-- it moves, resizes or maxChecks events pass.
local function moving()
  if state.moving then
    return true
  end
  if not state.win then
    state.win = hs.window.focusedWindow()
    if not state.win then
      state.done = true
      return false
    end
    state.start, state.checks = state.win:frame(), 0
    return false
  end
  local f, s = state.win:frame(), state.start
  if f.w ~= s.w or f.h ~= s.h then
    state.done = true
  elseif f.x ~= s.x or f.y ~= s.y then
    if host.pinned(state.win) then
      state.done = true
    else
      state.moving = true
    end
  else
    state.checks = state.checks + 1
    state.done = state.checks >= maxChecks
  end
  return state.moving == true
end

-- dragged follows the cursor and moves the footprint when the zone changes.
local function dragged()
  if not state.down or state.done or host.paused() or not host.snapOn() then
    return
  end
  if not moving() then
    return
  end
  local p = hs.mouse.absolutePosition()
  local s = screenAt(p)
  local zone = s and S.zone(p, s:fullFrame(), channelOf(s), state.zone) or nil
  local sid = s and s:id()
  if zone == state.zone and sid == state.sid then
    return
  end
  state.zone, state.screen, state.sid = zone, s, sid
  local frame = zone and actions.preview(state.win, zone, s)
  if frame then
    show(frame)
  else
    hide()
  end
end

-- released snaps the window when the drag ended in a zone. The move runs after
-- the event so the tap never waits on a window.
local function released()
  local win, zone, s = state.win, state.zone, state.screen
  reset()
  if win and zone then
    hs.timer.doAfter(0, function()
      local ok, err = pcall(actions.apply, win, zone, s)
      if not ok then
        host.log(err)
      end
    end)
  end
end

-- handle routes one mouse event. It always returns false so the event goes on
-- untouched.
function S.handle(e)
  local ok, err = pcall(function()
    local types, t = hs.eventtap.event.types, e:getType()
    if t == types.leftMouseDown then
      reset()
      state.down = true
    elseif t == types.leftMouseDragged then
      dragged()
    elseif t == types.leftMouseUp then
      released()
    end
  end)
  if not ok then
    reset()
    host.log(err)
  end
  return false
end

-- start watches mouse drags.
function S.start()
  local types = hs.eventtap.event.types
  reset()
  S.tap = hs.eventtap.new({ types.leftMouseDown, types.leftMouseDragged, types.leftMouseUp },
    S.handle):start()
end

return S
