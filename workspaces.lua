-- workspaces saves the slots, the strip widths and heights, and every free window's frame
-- under a name and puts them back on recall. A workspace tied to a display
-- setup comes back by itself when that setup is plugged in.

local geometry = require("geometry")

local W = {}

-- key is the Hammerspoon settings key the workspaces are saved under.
local key = "moorings.workspaces"

-- signature returns a name for a display setup from its screens' full frames,
-- the same whatever order the screens come in.
function W.signature(frames)
  local parts = {}
  for i, f in ipairs(frames) do
    parts[i] = string.format("%dx%d@%d,%d", f.w, f.h, f.x, f.y)
  end
  table.sort(parts)
  return table.concat(parts, " ")
end

-- match pairs saved window entries with live windows of the same app. A window
-- whose title matches wins, then any unused window of the app. It returns a
-- map from saved index to live index.
function W.match(saved, live)
  local used, out = {}, {}
  for pass = 1, 2 do
    for i, e in ipairs(saved) do
      if not out[i] then
        for j, l in ipairs(live) do
          if not used[j] and l.bundle == e.bundle and (pass == 2 or l.title == e.title) then
            used[j], out[i] = true, j
            break
          end
        end
      end
    end
  end
  return out
end

local host
local state = {}

-- attach gives workspaces the anchors module and remembers the display setup
-- in place at load, so a reload does not recall anything.
function W.attach(m)
  host = m
  state.setup = W.setup()
end

-- all returns the saved workspaces by name.
local function all()
  local saved = hs.settings.get(key)
  return type(saved) == "table" and saved or {}
end

-- store saves the workspaces by name.
local function store(list)
  hs.settings.set(key, list)
end

-- names returns the saved workspace names, sorted.
function W.names()
  local out = {}
  for name in pairs(all()) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

-- setup returns the signature of the displays attached now.
function W.setup()
  local frames = {}
  for i, s in ipairs(hs.screen.allScreens()) do
    frames[i] = s:fullFrame()
  end
  return W.signature(frames)
end

-- describe returns the app and title of win for matching on recall.
local function describe(win)
  local app = win:application()
  return { bundle = app and app:bundleID(), title = win:title() or "" }
end

-- save stores the layout in effect under name, keeping the display tie of a
-- workspace it replaces.
function W.save(name)
  local list = all()
  local left, right = host.widths()
  local leftTop, rightTop = host.heights()
  local windows = {}
  for _, w in ipairs(host.freeWindows()) do
    local d = describe(w)
    if d.bundle then
      local f = w:frame()
      d.frame = { x = f.x, y = f.y, w = f.w, h = f.h }
      windows[#windows + 1] = d
    end
  end
  local old = list[name]
  list[name] = {
    slots = host.assignments(),
    left = left,
    right = right,
    heights = { left = leftTop, right = rightTop },
    windows = windows,
    setup = type(old) == "table" and old.setup or nil,
  }
  store(list)
end

-- fit returns f clamped into the area of the screen holding its center, or nil
-- when no screen holds it.
local function fit(f)
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  for _, s in ipairs(hs.screen.allScreens()) do
    local full = s:fullFrame()
    if cx >= full.x and cx < full.x + full.w and cy >= full.y and cy < full.y + full.h then
      return geometry.clamp(f, host.area(s))
    end
  end
  return nil
end

-- recall puts back the workspace saved as name and reports whether it existed.
-- Windows whose app is not running, or whose display is gone, stay where they
-- are, and the Console says how many.
function W.recall(name)
  if host.paused() then
    return false
  end
  local ws = all()[name]
  if type(ws) ~= "table" then
    host.log("no workspace is named " .. tostring(name))
    return false
  end
  host.setLayout(ws.slots, ws.left, ws.right, ws.heights)
  local live, info = host.freeWindows(), {}
  for i, w in ipairs(live) do
    info[i] = describe(w)
  end
  local saved = type(ws.windows) == "table" and ws.windows or {}
  local matched = W.match(saved, info)
  local missed = 0
  for i, e in ipairs(saved) do
    local j = matched[i]
    local target = j and type(e.frame) == "table" and fit(e.frame)
    if target then
      host.save(live[j])
      live[j]:setFrame(target)
    else
      missed = missed + 1
    end
  end
  if missed > 0 then
    host.log(string.format("workspace %s: %d windows had no running app or display", name, missed))
  end
  host.moor()
  return true
end

-- delete removes the workspace saved as name.
function W.delete(name)
  local list = all()
  list[name] = nil
  store(list)
end

-- tied reports whether the workspace name comes back when the displays
-- attached now are plugged in.
function W.tied(name)
  local ws = all()[name]
  return type(ws) == "table" and ws.setup ~= nil and ws.setup == W.setup()
end

-- tie makes name come back when the displays attached now are plugged in, or
-- unties it. One workspace holds each display setup.
function W.tie(name)
  local list, setup = all(), W.setup()
  local ws = list[name]
  if type(ws) ~= "table" then
    return
  end
  if ws.setup == setup then
    ws.setup = nil
  else
    for _, other in pairs(list) do
      if type(other) == "table" and other.setup == setup then
        other.setup = nil
      end
    end
    ws.setup = setup
  end
  store(list)
end

-- screensChanged recalls the workspace tied to the display setup just plugged
-- in. The setup in place when moorings starts is taken as already handled.
function W.screensChanged()
  local setup = W.setup()
  if state.setup == setup then
    return false
  end
  state.setup = setup
  for _, name in ipairs(W.names()) do
    if all()[name].setup == setup then
      return W.recall(name)
    end
  end
  return false
end

return W
