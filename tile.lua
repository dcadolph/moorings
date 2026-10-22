-- tile organizes every free window on a screen at once: columns, rows, a grid,
-- a cascade, a mirror, and a walk through windows stacked on one frame. The
-- frame math is pure and runs without Hammerspoon.

local geometry = require("geometry")

local T = {}

-- names lists the organize actions in menu order. The names match Rectangle's
-- where Rectangle has the action.
T.names = {
  "tile-columns", "tile-rows", "tile-all", "cascade-all", "cascade-active-app",
  "cycle-stacked-windows", "cycle-stacked-windows-backward", "reverse-all",
}

-- cascadeStep is how far in points each cascaded window sits from the last.
T.cascadeStep = 30

-- columns returns n side by side frames filling area.
function T.columns(area, n, gap)
  local out = {}
  for i = 1, n do
    out[i] = geometry.part(area, i - 1, i, n, 0, 1, 1, gap)
  end
  return out
end

-- rows returns n stacked frames filling area.
function T.rows(area, n, gap)
  local out = {}
  for i = 1, n do
    out[i] = geometry.part(area, 0, 1, 1, i - 1, i, n, gap)
  end
  return out
end

-- grid returns n frames in a near square grid read left to right, top to
-- bottom. A short last row widens its frames so the area has no hole.
function T.grid(area, n, gap)
  local cols = math.ceil(math.sqrt(n))
  local rows = math.ceil(n / cols)
  local out = {}
  for k = 1, n do
    local r, c = math.floor((k - 1) / cols), (k - 1) % cols
    local inRow = math.min(cols, n - r * cols)
    out[k] = geometry.part(area, c, c + 1, inRow, r, r + 1, rows, gap)
  end
  return out
end

-- cascade returns frames for windows of the given frames, back-most first,
-- each stepped down and right from the last. Windows keep their size unless
-- the stack would leave the area, and the step shrinks when many windows would
-- push the stack past half the area.
function T.cascade(area, frames, step)
  local n = #frames
  if n > 1 then
    step = math.min(step, math.floor(area.w / 2 / (n - 1)), math.floor(area.h / 2 / (n - 1)))
  end
  local off = (n - 1) * step
  local out = {}
  for i, f in ipairs(frames) do
    out[i] = {
      x = area.x + (i - 1) * step,
      y = area.y + (i - 1) * step,
      w = math.min(f.w, area.w - off),
      h = math.min(f.h, area.h - off),
    }
  end
  return out
end

-- reverse returns f mirrored left to right across area.
function T.reverse(area, f)
  return { x = area.x + area.w - (f.x - area.x) - f.w, y = f.y, w = f.w, h = f.h }
end

local host, actions

-- attach gives tile the anchors module and the action runner.
function T.attach(m, a)
  host, actions = m, a
end

-- handles reports whether name is an organize action.
function T.handles(name)
  for _, n in ipairs(T.names) do
    if n == name then
      return true
    end
  end
  return false
end

-- byX orders windows left to right, then top to bottom, then by id.
local function byX(a, b)
  local fa, fb = a:frame(), b:frame()
  if fa.x ~= fb.x then
    return fa.x < fb.x
  elseif fa.y ~= fb.y then
    return fa.y < fb.y
  end
  return a:id() < b:id()
end

-- byY orders windows top to bottom, then left to right, then by id.
local function byY(a, b)
  local fa, fb = a:frame(), b:frame()
  if fa.y ~= fb.y then
    return fa.y < fb.y
  elseif fa.x ~= fb.x then
    return fa.x < fb.x
  end
  return a:id() < b:id()
end

-- place moves each window in list to the frame at the same index, saving
-- where each was first so Undo tidy and Restore can put it back.
local function place(list, frames)
  for i, w in ipairs(list) do
    host.save(w)
    w:setFrame(frames[i])
  end
  return #list > 0
end

-- tileOn lays out the windows of list on screen s with layout, after sorting
-- them with order.
local function tileOn(s, list, layout, order)
  table.sort(list, order)
  return place(list, layout(host.area(s), #list, actions.gap()))
end

-- tidy tiles the n front-most free windows on s into equal columns, keeping
-- their left to right order.
function T.tidy(s, n)
  local list = {}
  for i, w in ipairs(host.organizable(s)) do
    if i > n then
      break
    end
    list[i] = w
  end
  return tileOn(s, list, T.columns, byX)
end

-- cascadeList cascades list on s, back-most window first so the front-most
-- stays on top at the end of the stack.
local function cascadeList(s, list)
  local back, frames = {}, {}
  for i = #list, 1, -1 do
    back[#back + 1] = list[i]
    frames[#frames + 1] = list[i]:frame()
  end
  return place(back, T.cascade(host.area(s), frames, T.cascadeStep))
end

-- stacked returns the windows sharing win's frame on s, ordered by id.
local function stacked(s, win)
  local f, out = win:frame(), {}
  for _, w in ipairs(host.organizable(s)) do
    if host.near(w:frame(), f) then
      out[#out + 1] = w
    end
  end
  table.sort(out, function(a, b)
    return a:id() < b:id()
  end)
  return out
end

-- cycle focuses the next window in win's stack, or the previous when dir is -1.
local function cycle(s, win, dir)
  local list = stacked(s, win)
  for i, w in ipairs(list) do
    if w:id() == win:id() then
      list[(i - 1 + dir) % #list + 1]:focus()
      return true
    end
  end
  return false
end

-- run applies organize action name on the focused window's screen and reports
-- whether anything changed.
function T.run(name)
  local win = hs.window.focusedWindow()
  local s = win and win:screen()
  if not s then
    return false
  end
  if name == "tile-columns" then
    return tileOn(s, host.organizable(s), T.columns, byX)
  elseif name == "tile-rows" then
    return tileOn(s, host.organizable(s), T.rows, byY)
  elseif name == "tile-all" then
    return tileOn(s, host.organizable(s), T.grid, byY)
  elseif name == "cascade-all" then
    return cascadeList(s, host.organizable(s))
  elseif name == "cascade-active-app" then
    local app, list = win:application():bundleID(), {}
    for _, w in ipairs(host.organizable(s)) do
      if w:application():bundleID() == app then
        list[#list + 1] = w
      end
    end
    return cascadeList(s, list)
  elseif name == "cycle-stacked-windows" then
    return cycle(s, win, 1)
  elseif name == "cycle-stacked-windows-backward" then
    return cycle(s, win, -1)
  elseif name == "reverse-all" then
    local area, list, frames = host.area(s), host.organizable(s), {}
    for i, w in ipairs(list) do
      frames[i] = T.reverse(area, w:frame())
    end
    return place(list, frames)
  end
  return false
end

return T
