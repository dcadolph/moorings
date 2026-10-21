-- anchors pins chosen apps to the edges of an ultrawide screen and keeps every
-- other window in the channel between them.

local M = {}

-- config holds the pins, widths and timing. Edit it, then choose Reload.
M.config = {
  -- pins lists the apps held at an edge, by bundle ID. expandPct widens a pin
  -- while it has focus, and mainOnly moves only the app's main window.
  pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left", expandPct = 30, mainOnly = true },
    { bundle = "com.googlecode.iterm2", side = "right" },
  },
  -- ignoreBundles lists apps whose windows are never moved.
  ignoreBundles = {},
  -- leftPct and rightPct are the edge widths until a preset is chosen.
  leftPct = 10,
  rightPct = 45,
  -- pollSeconds is how often the layout is re-checked between window events.
  pollSeconds = 0.25,
  -- minAspect is the width-to-height ratio a screen needs to count as ultrawide.
  minAspect = 2.2,
  -- tolerance is how many points a frame may drift before it is corrected.
  tolerance = 2,
}

-- presets are the width pairs offered in the menu.
M.presets = {
  { left = 8, right = 46 },
  { left = 10, right = 45 },
  { left = 10, right = 40 },
  { left = 10, right = 30 },
  { left = 15, right = 40 },
  { left = 15, right = 30 },
  { left = 20, right = 40 },
}

-- icons are the menu bar glyphs offered in the Icon submenu.
M.icons = {
  { name = "Sailboat", glyph = "⛵" },
  { name = "Motor boat", glyph = "🛥️" },
  { name = "Speedboat", glyph = "🚤" },
  { name = "Canoe", glyph = "🛶" },
  { name = "Rowboat", glyph = "🚣" },
  { name = "Ferry", glyph = "⛴️" },
  { name = "Ship", glyph = "🚢" },
  { name = "Passenger ship", glyph = "🛳️" },
  { name = "Anchor", glyph = "⚓" },
  { name = "Ring buoy", glyph = "🛟" },
  { name = "Compass", glyph = "🧭" },
  { name = "Wave", glyph = "🌊" },
  { name = "Ladder", glyph = "🪜" },
  { name = "Orange heart", glyph = "🧡" },
  { name = "Pushpin", glyph = "📌" },
  { name = "Octopus", glyph = "🐙" },
  { name = "Crab", glyph = "🦀" },
  { name = "Turtle", glyph = "🐢" },
}

local keys = {
  preset = "moorings.preset",
  icon = "moorings.icon",
  paused = "moorings.paused",
  fullscreen = "moorings.fullscreenFills",
}

-- minChannelPct is the narrowest channel a width pair may leave.
local minChannelPct = 10

-- burstMoves moves of one window inside burstSeconds put it on hold for holdSeconds.
local burstMoves, burstSeconds, holdSeconds = 4, 10, 60

-- pendingSeconds is how long a window leaving fullscreen waits for its fill.
local pendingSeconds = 5

-- repeatSeconds is how long an identical log message stays quiet.
local repeatSeconds = 60

local state = {
  -- saved maps a window id to its frame from before the first Fill or Tidy move.
  saved = {},
  -- pendingFill maps a window leaving native fullscreen to when it left.
  pendingFill = {},
  -- bursts tracks how often each window is moved back toward the same frame.
  bursts = {},
  -- logged maps a log message to when it was last printed.
  logged = {},
  -- axWarned is set once the missing Accessibility permission has been logged.
  axWarned = false,
  -- clamped maps a window id to the width it had before the channel narrowed it.
  clamped = {},
}

-- now returns the current time in seconds.
function M.now()
  return hs.timer.secondsSinceEpoch()
end

-- log prints a message to the Hammerspoon Console at most once per repeatSeconds.
local function log(msg)
  msg = "moorings: " .. tostring(msg)
  local t = M.now()
  local last = state.logged[msg]
  if last and t - last < repeatSeconds then
    return
  end
  state.logged[msg] = t
  print(msg)
end

-- safe wraps fn so an error is logged instead of breaking the caller.
local function safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      log(err)
    end
  end
end

-- rect copies the x, y, w and h of a frame into a plain table.
local function rect(f)
  return { x = f.x, y = f.y, w = f.w, h = f.h }
end

-- near reports whether two frames match within the configured tolerance.
local function near(a, b)
  local t = M.config.tolerance
  return math.abs(a.x - b.x) <= t and math.abs(a.y - b.y) <= t
    and math.abs(a.w - b.w) <= t and math.abs(a.h - b.h) <= t
end

-- place moves win to frame unless it is already there. A window that keeps
-- moving away from the same frame is left alone for holdSeconds.
local function place(win, frame)
  local id, t = win:id(), M.now()
  local b = state.bursts[id]
  if b and not near(b.target, frame) then
    b = nil
  end
  if b and b.holdUntil and t < b.holdUntil then
    return
  end
  if near(win:frame(), frame) then
    return
  end
  win:setFrame(frame)
  b = b or { target = rect(frame), moves = 0, since = t }
  b.holdUntil = nil
  if t - b.since > burstSeconds then
    b.moves, b.since = 0, t
  end
  b.moves = b.moves + 1
  if b.moves >= burstMoves then
    b.moves, b.since, b.holdUntil = 0, t, t + holdSeconds
    log("window " .. tostring(id) .. " keeps moving back: leaving it for " .. holdSeconds .. " s")
  end
  state.bursts[id] = b
end

-- sameScreen reports whether two screens are the same display.
local function sameScreen(a, b)
  return a ~= nil and b ~= nil and a:id() == b:id()
end

-- paused reports whether the layout is frozen.
local function paused()
  return hs.settings.get(keys.paused) == true
end

-- fullscreenFills reports whether native fullscreen is redirected to the channel.
local function fullscreenFills()
  return hs.settings.get(keys.fullscreen) ~= false
end

-- validSplit reports whether left and right widths leave a usable channel.
local function validSplit(left, right)
  return type(left) == "number" and type(right) == "number"
    and left > 0 and right > 0 and left + right <= 100 - minChannelPct
end

-- widths returns the left and right edge percentages in effect.
function M.widths()
  local i = hs.settings.get(keys.preset)
  local p = i and M.presets[i]
  if p then
    return p.left, p.right
  end
  local c = M.config
  if validSplit(c.leftPct, c.rightPct) then
    return c.leftPct, c.rightPct
  end
  log("leftPct and rightPct leave no channel: using 10 and 45")
  return 10, 45
end

-- edge returns the frame an edge of pct width occupies on f.
function M.edge(f, side, pct)
  local w = math.floor(f.w * pct / 100)
  if side == "right" then
    return { x = f.x + f.w - w, y = f.y, w = w, h = f.h }
  end
  return { x = f.x, y = f.y, w = w, h = f.h }
end

-- regions splits f into the left edge, the channel and the right edge.
function M.regions(f, leftPct, rightPct)
  local left = M.edge(f, "left", leftPct)
  local right = M.edge(f, "right", rightPct)
  return {
    left = left,
    channel = { x = left.x + left.w, y = f.y, w = right.x - left.x - left.w, h = f.h },
    right = right,
  }
end

-- ultrawide returns the widest screen at or above minAspect, or nil.
function M.ultrawide()
  local best, bestRatio = nil, 0
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    local ratio = f.h > 0 and f.w / f.h or 0
    if ratio >= M.config.minAspect and ratio > bestRatio then
      best, bestRatio = s, ratio
    end
  end
  return best
end

-- channel returns the channel frame on screen s.
function M.channel(s)
  return M.regions(s:frame(), M.widths()).channel
end

-- bundleOf returns the bundle ID of win's app, or nil.
local function bundleOf(win)
  local app = win:application()
  return app and app:bundleID()
end

-- ignored reports whether win belongs to an app in ignoreBundles.
local function ignored(win)
  local bundle = bundleOf(win)
  for _, id in ipairs(M.config.ignoreBundles) do
    if id == bundle then
      return true
    end
  end
  return bundle == nil
end

-- pinFor returns the pin entry for win's app, or nil.
function M.pinFor(win)
  local bundle = bundleOf(win)
  for _, pin in ipairs(M.config.pins) do
    if pin.bundle == bundle then
      return pin
    end
  end
  return nil
end

-- pinsWindow reports whether pin applies to win, honoring mainOnly.
local function pinsWindow(pin, win)
  if not pin.mainOnly then
    return true
  end
  local main = win:application():mainWindow()
  return main ~= nil and main:id() == win:id()
end

-- mouseHeld reports whether the primary mouse button is down, as during a drag.
local function mouseHeld()
  local ok, buttons = pcall(hs.mouse.getButtons)
  return ok and type(buttons) == "table" and buttons[1] == true
end

-- trusted reports whether Accessibility is granted, logging once when it is not.
local function trusted()
  if hs.accessibilityState() then
    state.axWarned = false
    return true
  end
  if not state.axWarned then
    print("moorings: Accessibility is not granted: windows will not move")
    state.axWarned = true
  end
  return false
end

-- clamp fits f inside ch, shrinking it only when it is larger than ch.
function M.clamp(f, ch)
  local w = math.min(f.w, ch.w)
  local h = math.min(f.h, ch.h)
  return {
    x = math.max(ch.x, math.min(f.x, ch.x + ch.w - w)),
    y = math.max(ch.y, math.min(f.y, ch.y + ch.h - h)),
    w = w,
    h = h,
  }
end

-- movable reports whether moorings may move win at all.
local function movable(win)
  return win:id() ~= nil and win:isStandard() and not win:isMinimized() and not ignored(win)
end

-- windows returns the movable windows, front-most first.
local function windows()
  local list, seen = {}, {}
  local focused = hs.window.focusedWindow()
  if focused and movable(focused) then
    list[1], seen[focused:id()] = focused, true
  end
  for _, w in ipairs(hs.window.orderedWindows()) do
    if not seen[w:id()] and movable(w) and w:isVisible() then
      list[#list + 1], seen[w:id()] = w, true
    end
  end
  return list
end

-- freeWindows returns the unpinned, windowed windows on screen s, front-most first.
local function freeWindows(s)
  local list = {}
  for _, w in ipairs(windows()) do
    if not M.pinFor(w) and not w:isFullScreen() and sameScreen(w:screen(), s) then
      list[#list + 1] = w
    end
  end
  return list
end

-- save records win's frame once, before Fill or Tidy first moves it.
local function save(win)
  local id = win:id()
  if not state.saved[id] then
    state.saved[id] = rect(win:frame())
  end
  state.clamped[id] = nil
end

-- settle keeps a free window inside the channel and lets a window the channel
-- once narrowed grow back toward its old width when the channel widens.
local function settle(win, ch)
  local id, cur = win:id(), win:frame()
  local c = state.clamped[id]
  if c and math.abs(cur.w - c.set) > M.config.tolerance then
    c = nil
  end
  local f = rect(cur)
  if c then
    f.w = c.natural
  end
  local want = M.clamp(f, ch)
  if want.w < f.w then
    state.clamped[id] = { natural = f.w, set = want.w }
  else
    state.clamped[id] = nil
  end
  place(win, want)
end

-- moor puts every pin on its edge and every free window in the channel.
function M.moor()
  if paused() or mouseHeld() or not trusted() then
    return
  end
  local s = M.ultrawide()
  if not s then
    return
  end
  local frame = s:frame()
  local leftPct, rightPct = M.widths()
  local pct = { left = leftPct, right = rightPct }
  local ch = M.regions(frame, leftPct, rightPct).channel
  local focused = hs.window.focusedWindow()
  local focusedPin = focused and M.pinFor(focused)
  local t, seen = M.now(), {}
  for _, w in ipairs(windows()) do
    local pin = M.pinFor(w)
    seen[w:id()] = true
    if pin then
      if not w:isFullScreen() and pinsWindow(pin, w) then
        local width = (pin == focusedPin and pin.expandPct) or pct[pin.side]
        place(w, M.edge(frame, pin.side, width))
      end
    elseif sameScreen(w:screen(), s) then
      local id = w:id()
      if w:isFullScreen() then
        local started = state.pendingFill[id]
        if fullscreenFills() and not (started and t - started <= pendingSeconds) then
          state.pendingFill[id] = t
          w:setFullScreen(false)
        end
      elseif state.pendingFill[id] then
        local started = state.pendingFill[id]
        state.pendingFill[id] = nil
        state.clamped[id] = nil
        if t - started <= pendingSeconds then
          place(w, ch)
        else
          settle(w, ch)
        end
      else
        settle(w, ch)
      end
    end
  end
  for _, tbl in ipairs({ state.clamped, state.bursts, state.pendingFill }) do
    for id in pairs(tbl) do
      if not seen[id] then
        tbl[id] = nil
      end
    end
  end
end

-- fill stretches the focused free window across the whole channel.
function M.fill()
  if paused() then
    return
  end
  local s = M.ultrawide()
  local win = hs.window.focusedWindow()
  if not s or not win or M.pinFor(win) or win:isFullScreen() then
    return
  end
  save(win)
  win:setFrame(M.channel(s))
end

-- tidy tiles the n front-most free windows into equal columns, left to right
-- in their current order.
function M.tidy(n)
  if paused() then
    return
  end
  local s = M.ultrawide()
  if not s then
    return
  end
  local list = {}
  for i, w in ipairs(freeWindows(s)) do
    if i > n then
      break
    end
    list[i] = w
  end
  if #list == 0 then
    return
  end
  table.sort(list, function(a, b)
    return a:frame().x < b:frame().x
  end)
  local ch = M.channel(s)
  local colW = math.floor(ch.w / #list)
  for i, w in ipairs(list) do
    save(w)
    local x = ch.x + (i - 1) * colW
    local width = (i == #list) and (ch.x + ch.w - x) or colW
    w:setFrame({ x = x, y = ch.y, w = width, h = ch.h })
  end
end

-- canUndo reports whether Fill or Tidy has moved anything since the last undo.
function M.canUndo()
  return next(state.saved) ~= nil
end

-- undo puts every window Fill or Tidy moved back where it was before the first move.
function M.undo()
  if paused() then
    return
  end
  for id, f in pairs(state.saved) do
    local w = hs.window.get(id)
    if w then
      w:setFrame(f)
    end
  end
  state.saved = {}
end

-- iconGlyph returns the glyph of the chosen icon.
local function iconGlyph()
  local name = hs.settings.get(keys.icon)
  for _, icon in ipairs(M.icons) do
    if icon.name == name then
      return icon.glyph
    end
  end
  return M.icons[1].glyph
end

-- menu builds the menu bar menu from current state.
local function menu()
  local frozen = paused()
  local items = {
    {
      title = frozen and "⚓ Weigh anchor (resume layout)" or "⚓ Drop anchor (freeze layout)",
      fn = safe(function()
        hs.settings.set(keys.paused, not paused())
        M.moor()
      end),
    },
    {
      title = "Re-moor now",
      disabled = frozen,
      fn = safe(function()
        state.bursts = {}
        M.moor()
      end),
    },
    { title = "Fill channel", disabled = frozen, fn = safe(M.fill) },
    {
      title = "Tidy channel",
      disabled = frozen,
      menu = {
        { title = "Halves", fn = safe(function() M.tidy(2) end) },
        { title = "Thirds", fn = safe(function() M.tidy(3) end) },
      },
    },
    { title = "Undo tidy", fn = safe(M.undo), disabled = frozen or not M.canUndo() },
    { title = "-" },
  }
  local leftPct, rightPct = M.widths()
  for i, p in ipairs(M.presets) do
    items[#items + 1] = {
      title = string.format("Left %d%%, right %d%%", p.left, p.right),
      checked = p.left == leftPct and p.right == rightPct,
      fn = safe(function()
        hs.settings.set(keys.preset, i)
        M.moor()
      end),
    }
  end
  local icons = {}
  local glyph = iconGlyph()
  for _, icon in ipairs(M.icons) do
    icons[#icons + 1] = {
      title = icon.glyph .. "  " .. icon.name,
      checked = icon.glyph == glyph,
      fn = safe(function()
        hs.settings.set(keys.icon, icon.name)
        M.bar:setTitle(icon.glyph)
      end),
    }
  end
  local rest = {
    { title = "-" },
    {
      title = "Fullscreen fills the channel",
      checked = fullscreenFills(),
      fn = safe(function() hs.settings.set(keys.fullscreen, not fullscreenFills()) end),
    },
    {
      title = "Edit config",
      fn = safe(function() hs.execute("open -t " .. hs.configdir .. "/anchors.lua") end),
    },
    { title = "Console", fn = safe(hs.openConsole) },
    { title = "Reload", fn = safe(hs.reload) },
    { title = "Icon", menu = icons },
  }
  for _, item in ipairs(rest) do
    items[#items + 1] = item
  end
  return items
end

-- menuOrError builds the menu, falling back to a pointer at the Console.
local function menuOrError()
  local ok, items = pcall(menu)
  if ok then
    return items
  end
  log(items)
  return { { title = "Menu failed, see Console", fn = hs.openConsole } }
end

-- start creates the menu bar item, subscribes to window events and starts polling.
function M.start()
  hs.window.animationDuration = 0
  hs.autoLaunch(true)
  hs.accessibilityState(true)
  for _, pin in ipairs(M.config.pins) do
    if type(pin.bundle) ~= "string" or (pin.side ~= "left" and pin.side ~= "right") then
      log("a pin needs a bundle and a side of left or right: check the config")
    end
  end
  M.bar = hs.menubar.new()
  M.bar:setTitle(iconGlyph())
  M.bar:setMenu(menuOrError)
  local wf = hs.window.filter
  M.filter = wf.default:subscribe({
    wf.windowCreated,
    wf.windowFocused,
    wf.windowFullscreened,
    wf.windowUnfullscreened,
  }, safe(M.moor))
  M.screens = hs.screen.watcher.new(safe(M.moor)):start()
  M.timer = hs.timer.doEvery(M.config.pollSeconds, safe(M.moor))
  safe(M.moor)()
  return M
end

return M
