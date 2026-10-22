-- anchors pins chosen apps to the edges of an ultrawide screen and keeps every
-- other window in the channel between them.

local actions = require("actions")
local geometry = require("geometry")
local snap = require("snap")
local tile = require("tile")
local workspaces = require("workspaces")
local settings = require("settings")

local M = {}

-- config holds the pins, widths and timing. Edit it, then choose Reload.
M.config = {
  -- pins lists the apps held at an edge, by bundle ID. A side holds at most two.
  -- row is "top" or "bottom" and only matters when two pins share a side.
  -- expandPct widens a pin while it has focus, and mainOnly moves only the
  -- app's main window.
  pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left", expandPct = 30, mainOnly = true },
    { bundle = "com.googlecode.iterm2", side = "right" },
  },
  -- ignoreBundles lists apps whose windows are never moved. Shortcuts are off
  -- while one of them is frontmost.
  ignoreBundles = {},
  -- keymap picks the built-in shortcut set, "rectangle" or "spectacle", until
  -- one is chosen from Settings, Keymap.
  keymap = "rectangle",
  -- shortcuts overrides the keymap by action name. Set an action to
  -- { mods = { "ctrl", "alt" }, key = "h" } to rebind it, or to false to unbind it.
  shortcuts = {},
  -- mouseButtons maps an extra mouse button number, 2 to 31, to an action, such
  -- as { [3] = "previous-display", [4] = "next-display" }.
  mouseButtons = {},
  -- sizes lists custom window sizes for the Window, Custom sizes folder. Each
  -- has a title, x, y, w and h as shares of the area from 0 to 1, an optional
  -- width and height in points centered in that share, and an optional shortcut.
  sizes = {},
  -- gapPx is the space in points around and between windows placed by an action.
  gapPx = 0,
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
  widths = "moorings.widths",
  icon = "moorings.icon",
  paused = "moorings.paused",
  fullscreen = "moorings.fullscreenFills",
  slots = "moorings.slots",
  ignoreShortcuts = "moorings.ignoreShortcuts",
  snap = "moorings.snap",
  keymap = "moorings.keymap",
  shortcuts = "moorings.shortcuts",
  sizes = "moorings.sizes",
  gap = "moorings.gapPx",
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
  -- saved maps a window id to its frame from before the first Fill, Tidy or
  -- window action moved it.
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

M.log = log

-- shellQuote wraps s in single quotes for the shell.
local function shellQuote(s)
  return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

-- loadfile compiles a config file without running it. Tests replace it.
M.loadfile = loadfile

-- files lists the moorings source files, which live in the moorings folder
-- inside the Hammerspoon config directory.
M.files = {
  "anchors.lua", "geometry.lua", "actions.lua", "snap.lua", "tile.lua", "workspaces.lua",
  "settings.lua",
}

-- path returns the full path of a moorings source file.
function M.path(file)
  return hs.configdir .. "/moorings/" .. file
end

-- reload reloads Hammerspoon only when every moorings file still compiles, so a
-- typo from Edit config cannot leave the layout dead.
function M.reload()
  for _, file in ipairs(M.files) do
    local chunk, err = M.loadfile(M.path(file))
    if not chunk then
      log("not reloading, the config has an error: " .. tostring(err))
      hs.alert.show("moorings: config error, see Console")
      return
    end
  end
  hs.reload()
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

M.near = near

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

M.paused = paused

-- keymap returns the name of the shortcut set in effect. A choice from the
-- menu wins over the config, and an unknown name falls back to rectangle.
function M.keymap()
  local saved = hs.settings.get(keys.keymap)
  if actions.keymaps[saved] then
    return saved
  end
  if actions.keymaps[M.config.keymap] then
    return M.config.keymap
  end
  log("keymap " .. tostring(M.config.keymap) .. " is unknown: using rectangle")
  return "rectangle"
end

-- setKeymap saves name as the shortcut set and rebinds every shortcut.
function M.setKeymap(name)
  hs.settings.set(keys.keymap, name)
  for _, problem in ipairs(actions.bind()) do
    log(problem)
  end
end

-- savedTable returns the table saved under k, or an empty one.
local function savedTable(k)
  local saved = hs.settings.get(k)
  return type(saved) == "table" and saved or {}
end

-- shortcutOverrides returns the config shortcuts with the ones saved from the
-- settings window laid over them, action by action.
function M.shortcutOverrides()
  local out = {}
  for name, sc in pairs(type(M.config.shortcuts) == "table" and M.config.shortcuts or {}) do
    out[name] = sc
  end
  for name, sc in pairs(savedTable(keys.shortcuts)) do
    out[name] = sc
  end
  return out
end

-- savedShortcuts returns the shortcuts saved from the settings window.
function M.savedShortcuts()
  return savedTable(keys.shortcuts)
end

-- saveShortcut saves sc for action name from the settings window and rebinds.
-- A nil sc drops the saved choice so the config or keymap applies again.
function M.saveShortcut(name, sc)
  local saved = savedTable(keys.shortcuts)
  saved[name] = sc
  hs.settings.set(keys.shortcuts, saved)
  return actions.bind()
end

-- savedSizes returns the custom sizes saved from the settings window.
function M.savedSizes()
  return savedTable(keys.sizes)
end

-- sizeList returns the config sizes with the saved ones laid over them by
-- title, then the saved sizes the config does not name.
function M.sizeList()
  local saved, byTitle, out, used = M.savedSizes(), {}, {}, {}
  for _, e in ipairs(saved) do
    if type(e) == "table" and e.title ~= nil then
      byTitle[e.title] = e
    end
  end
  for _, e in ipairs(type(M.config.sizes) == "table" and M.config.sizes or {}) do
    local title = type(e) == "table" and e.title
    if title ~= nil and byTitle[title] then
      out[#out + 1], used[title] = byTitle[title], true
    else
      out[#out + 1] = e
    end
  end
  for _, e in ipairs(saved) do
    if not (type(e) == "table" and used[e.title]) then
      out[#out + 1] = e
    end
  end
  return out
end

-- saveSizes saves list as the custom sizes from the settings window and rebinds.
function M.saveSizes(list)
  hs.settings.set(keys.sizes, list)
  return actions.bind()
end

-- gapPx returns the gap saved from the settings window, or the config's.
function M.gapPx()
  local saved = hs.settings.get(keys.gap)
  if type(saved) == "number" then
    return saved
  end
  return M.config.gapPx
end

-- saveGap saves the gap from the settings window.
function M.saveGap(px)
  hs.settings.set(keys.gap, px)
end

-- snapOn reports whether dragging a window to an edge snaps it.
function M.snapOn()
  return hs.settings.get(keys.snap) ~= false
end

-- setSnap turns snapping by dragging on or off.
function M.setSnap(on)
  hs.settings.set(keys.snap, on == true)
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

-- widths returns the left and right edge percentages in effect. A width chosen
-- from the menu wins over the config.
function M.widths()
  local saved = hs.settings.get(keys.widths)
  if type(saved) == "table" and validSplit(saved.left, saved.right) then
    return saved.left, saved.right
  end
  local c = M.config
  if validSplit(c.leftPct, c.rightPct) then
    return c.leftPct, c.rightPct
  end
  log("leftPct and rightPct leave no channel: using 10 and 45")
  return 10, 45
end

-- setWidths saves left and right as the edge widths and re-moors.
function M.setWidths(left, right)
  hs.settings.set(keys.widths, { left = left, right = right })
  M.moor()
end

-- stepped returns the widths after moving side by delta points, and whether
-- they still leave a usable channel.
local function stepped(side, delta)
  local left, right = M.widths()
  if side == "left" then
    left = left + delta
  else
    right = right + delta
  end
  return left, right, validSplit(left, right)
end

-- step widens or narrows side by delta points, refusing a step that would
-- leave the channel under minChannelPct or a strip at zero.
function M.step(side, delta)
  local left, right, ok = stepped(side, delta)
  if ok then
    M.setWidths(left, right)
  end
  return ok
end

-- The frame math lives in geometry, re-exported here for callers and tests.
M.edge, M.slot, M.regions, M.clamp = geometry.edge, geometry.slot, geometry.regions, geometry.clamp

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

-- area returns the frame window actions work in on screen s: the channel on the
-- ultrawide, and the whole usable frame on any other screen.
function M.area(s)
  local wide = M.ultrawide()
  if wide and s:id() == wide:id() then
    return M.channel(s)
  end
  return s:frame()
end

-- bundleOf returns the bundle ID of win's app, or nil.
local function bundleOf(win)
  local app = win:application()
  return app and app:bundleID()
end

-- ignoredBundle reports whether bundle is missing or listed in ignoreBundles.
local function ignoredBundle(bundle)
  for _, id in ipairs(M.config.ignoreBundles) do
    if id == bundle then
      return true
    end
  end
  return bundle == nil
end

-- ignored reports whether win belongs to an app in ignoreBundles.
local function ignored(win)
  return ignoredBundle(bundleOf(win))
end

-- parkable reports whether win's app may take a slot.
function M.parkable(win)
  return not ignored(win)
end

-- shortcutIgnores returns the bundles chosen with Ignore frontmost app.
local function shortcutIgnores()
  local saved = hs.settings.get(keys.ignoreShortcuts)
  return type(saved) == "table" and saved or {}
end

-- shortcutsIgnored reports whether shortcuts are off while bundle is frontmost.
function M.shortcutsIgnored(bundle)
  if bundle == nil then
    return false
  end
  for _, id in ipairs(shortcutIgnores()) do
    if id == bundle then
      return true
    end
  end
  return ignoredBundle(bundle)
end

-- toggleShortcutIgnore adds bundle to the shortcut ignore list, or removes it.
function M.toggleShortcutIgnore(bundle)
  local list, found = {}, false
  for _, id in ipairs(shortcutIgnores()) do
    if id == bundle then
      found = true
    else
      list[#list + 1] = id
    end
  end
  if not found then
    list[#list + 1] = bundle
  end
  hs.settings.set(keys.ignoreShortcuts, list)
  actions.refresh()
end

-- validRow reports whether row names a half of a strip.
local function validRow(row)
  return row == "top" or row == "bottom"
end

-- rowsOf gives the two pins sharing side a row each. An explicit row is honored
-- when it is free, and the rest fill the open rows in config order.
local function rowsOf(side, list, slots, problems)
  local taken, waiting = {}, {}
  for _, pin in ipairs(list) do
    if validRow(pin.row) and not taken[pin.row] then
      taken[pin.row] = pin
    else
      if validRow(pin.row) then
        problems[#problems + 1] = string.format(
          "%s and %s both ask for the %s row on the %s: %s takes the other",
          taken[pin.row].bundle, pin.bundle, pin.row, side, pin.bundle)
      end
      waiting[#waiting + 1] = pin
    end
  end
  for _, row in ipairs({ "top", "bottom" }) do
    if not taken[row] then
      taken[row] = table.remove(waiting, 1)
    end
  end
  for row, pin in pairs(taken) do
    slots[pin.bundle] = { pin = pin, side = side, row = row }
  end
end

-- layout resolves pins into slots keyed by bundle ID and lists the problems it
-- found. A slot holds the pin, its side, and its row, which is nil when the pin
-- has its side to itself and fills the full height. A side holds two pins at most.
function M.layout(pins)
  local slots, problems, seen = {}, {}, {}
  local sides = { left = {}, right = {} }
  for _, pin in ipairs(pins) do
    local list = sides[pin.side]
    if type(pin.bundle) ~= "string" or not list then
      problems[#problems + 1] = "a pin needs a bundle and a side of left or right: check the config"
    elseif seen[pin.bundle] then
      problems[#problems + 1] = pin.bundle .. " is pinned twice: the first entry wins"
    elseif #list == 2 then
      problems[#problems + 1] = string.format("%s is a third pin on the %s: ignoring it",
        pin.bundle, pin.side)
    else
      if pin.row ~= nil and not validRow(pin.row) then
        problems[#problems + 1] = string.format("%s has row %s: use top or bottom",
          pin.bundle, tostring(pin.row))
      end
      seen[pin.bundle] = true
      list[#list + 1] = pin
    end
  end
  for _, side in ipairs({ "left", "right" }) do
    local list = sides[side]
    if #list == 1 then
      slots[list[1].bundle] = { pin = list[1], side = side }
    elseif #list == 2 then
      rowsOf(side, list, slots, problems)
    end
  end
  return slots, problems
end

-- slotNames lists the four slots in menu order.
M.slotNames = {
  { key = "left-top", side = "left", row = "top", title = "Left top" },
  { key = "left-bottom", side = "left", row = "bottom", title = "Left bottom" },
  { key = "right-top", side = "right", row = "top", title = "Right top" },
  { key = "right-bottom", side = "right", row = "bottom", title = "Right bottom" },
}

-- chosen returns the switcher's slot assignments, or nil when the config is in
-- effect. Each slot maps to a bundle ID, or to "" when it is empty.
local function chosen()
  local saved = hs.settings.get(keys.slots)
  if type(saved) ~= "table" then
    return nil
  end
  local out = {}
  for _, s in ipairs(M.slotNames) do
    out[s.key] = type(saved[s.key]) == "string" and saved[s.key] or ""
  end
  return out
end

-- configPin returns the config entry for bundle, or nil.
local function configPin(bundle)
  for _, pin in ipairs(M.config.pins) do
    if pin.bundle == bundle then
      return pin
    end
  end
  return nil
end

-- pins returns the pins in effect. Switcher choices override the config, and a
-- chosen app keeps the expandPct and mainOnly the config gives it.
function M.pins()
  local picks = chosen()
  if not picks then
    return M.config.pins
  end
  local list = {}
  for _, s in ipairs(M.slotNames) do
    local bundle = picks[s.key]
    if bundle ~= "" then
      local base = configPin(bundle) or {}
      list[#list + 1] = { bundle = bundle, side = s.side, row = s.row,
        expandPct = base.expandPct, mainOnly = base.mainOnly }
    end
  end
  return list
end

-- assignments returns the bundle in each slot of the layout in effect, with ""
-- for an empty slot. A pin filling its strip shows in the top slot.
function M.assignments()
  local picks = chosen()
  if picks then
    return picks
  end
  local out = {}
  for _, s in ipairs(M.slotNames) do
    out[s.key] = ""
  end
  for bundle, slot in pairs(M.layout(M.config.pins)) do
    out[slot.side .. "-" .. (slot.row or "top")] = bundle
  end
  return out
end

-- assign puts bundle in the slot named key and saves the result. An app already
-- in another slot moves, and a bundle of "" empties the slot.
function M.assign(key, bundle)
  local picks = M.assignments()
  for k, v in pairs(picks) do
    if v == bundle then
      picks[k] = ""
    end
  end
  picks[key] = bundle
  hs.settings.set(keys.slots, picks)
  M.moor()
end

-- resetSlots drops the switcher choices so the config is in effect again.
function M.resetSlots()
  hs.settings.clear(keys.slots)
  M.moor()
end

-- slotFrame returns the frame of the slot named key, such as left-top, on
-- screen s at the side's current width.
function M.slotFrame(s, key)
  local side, row = key:match("^(%a+)-(%a+)$")
  local leftPct, rightPct = M.widths()
  return M.slot(s:frame(), side, row, side == "left" and leftPct or rightPct)
end

-- slotFor returns the slot of win's app, or nil when the app is not pinned.
function M.slotFor(win)
  local slots = M.layout(M.pins())
  return slots[bundleOf(win)]
end

-- pinsWindow reports whether pin applies to win, honoring mainOnly.
local function pinsWindow(pin, win)
  if not pin.mainOnly then
    return true
  end
  local main = win:application():mainWindow()
  return main ~= nil and main:id() == win:id()
end

-- pinned reports whether the layout holds win at an edge, which only happens
-- while an ultrawide is attached.
function M.pinned(win)
  if not M.ultrawide() then
    return false
  end
  local slot = M.slotFor(win)
  return slot ~= nil and pinsWindow(slot.pin, win)
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

-- freeWindows returns every window on any screen that is not pinned and not
-- fullscreen, front-most first.
function M.freeWindows()
  local list = {}
  for _, w in ipairs(windows()) do
    if not M.pinned(w) and not w:isFullScreen() then
      list[#list + 1] = w
    end
  end
  return list
end

-- setLayout saves slots and the strip widths without re-mooring. A value that
-- is missing or leaves no channel is skipped.
function M.setLayout(slots, left, right)
  if type(slots) == "table" then
    hs.settings.set(keys.slots, slots)
  end
  if validSplit(left, right) then
    hs.settings.set(keys.widths, { left = left, right = right })
  end
end

M.recallWorkspace = workspaces.recall

-- organizable returns the windows on screen s that organize actions may move:
-- not pinned and not fullscreen, front-most first.
function M.organizable(s)
  local list = {}
  for _, w in ipairs(windows()) do
    if not M.pinned(w) and not w:isFullScreen() and sameScreen(w:screen(), s) then
      list[#list + 1] = w
    end
  end
  return list
end

-- save records win's frame once, before Fill, Tidy or a window action first
-- moves it.
local function save(win)
  local id = win:id()
  if not state.saved[id] then
    state.saved[id] = rect(win:frame())
  end
  state.clamped[id] = nil
end

M.save = save

-- restore puts win back where it was before the first move moorings made, and
-- reports whether there was a frame to return to.
function M.restore(win)
  local id = win:id()
  local f = state.saved[id]
  if not f then
    return false
  end
  state.saved[id] = nil
  state.clamped[id] = nil
  win:setFrame(f)
  return true
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
  local slots = M.layout(M.pins())
  local focused = hs.window.focusedWindow()
  local focusedSlot = focused and slots[bundleOf(focused)]
  local t, seen = M.now(), {}
  for _, w in ipairs(windows()) do
    local slot = slots[bundleOf(w)]
    seen[w:id()] = true
    if slot then
      if not w:isFullScreen() and pinsWindow(slot.pin, w) then
        local width = (slot == focusedSlot and slot.pin.expandPct) or pct[slot.side]
        place(w, M.slot(frame, slot.side, slot.row, width))
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
  if not s or not win or M.slotFor(win) or win:isFullScreen() then
    return
  end
  save(win)
  win:setFrame(M.channel(s))
end

-- tidy tiles the n front-most free windows into equal columns, left to right
-- in their current order. It works in the channel while the ultrawide is
-- attached, and on the focused window's screen otherwise.
function M.tidy(n)
  if paused() then
    return
  end
  local focused = hs.window.focusedWindow()
  local s = M.ultrawide() or (focused and focused:screen())
  if s then
    tile.tidy(s, n)
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

-- appName returns a display name for bundle, or Empty for an empty slot.
local function appName(bundle)
  if bundle == "" then
    return "Empty"
  end
  local ok, name = pcall(hs.application.nameForBundleID, bundle)
  return ok and name or bundle
end

-- runningApps returns the running Dock apps that can be locked, sorted by name.
local function runningApps()
  local list, seen = {}, {}
  for _, app in ipairs(hs.application.runningApplications()) do
    local bundle = app:bundleID()
    if app:kind() == 1 and not ignoredBundle(bundle) and not seen[bundle] then
      seen[bundle] = true
      list[#list + 1] = { bundle = bundle, name = app:name() or bundle }
    end
  end
  table.sort(list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return list
end

-- lockedItems builds the Locked apps folder: a row per slot that opens a list
-- of running apps, a fast path for the frontmost app, and a reset.
local function lockedItems()
  local picks, apps = M.assignments(), runningApps()
  local items = {}
  for _, s in ipairs(M.slotNames) do
    local current = picks[s.key]
    local choices = {
      { title = "Empty", checked = current == "", fn = safe(function() M.assign(s.key, "") end) },
    }
    for _, app in ipairs(apps) do
      choices[#choices + 1] = {
        title = app.name,
        checked = app.bundle == current,
        fn = safe(function() M.assign(s.key, app.bundle) end),
      }
    end
    items[#items + 1] = { title = s.title .. ": " .. appName(current), menu = choices }
  end
  local front = hs.application.frontmostApplication()
  local frontBundle = front and front:bundleID()
  local targets = {}
  for _, s in ipairs(M.slotNames) do
    targets[#targets + 1] = {
      title = s.title,
      checked = picks[s.key] == frontBundle,
      fn = safe(function() M.assign(s.key, frontBundle) end),
    }
  end
  local pinTitle = "Pin frontmost app"
  if front then
    pinTitle = pinTitle .. " (" .. (front:name() or frontBundle) .. ")"
  end
  items[#items + 1] = { title = pinTitle, disabled = ignoredBundle(frontBundle), menu = targets }
  items[#items + 1] = {
    title = "Reset to defaults",
    disabled = chosen() == nil,
    fn = safe(M.resetSlots),
  }
  return items
end

-- windowItems builds the Window folder, with Fill channel, Tidy channel and
-- Undo tidy at the end of Organize.
local function windowItems()
  local frozen = paused()
  return actions.menu({
    { title = "-" },
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
  })
end

-- widthItems builds the Widths folder: the channel label, the steppers and
-- the presets.
local function widthItems()
  local items = {}
  local leftPct, rightPct = M.widths()
  items[#items + 1] = {
    title = string.format("Channel %g%%", 100 - leftPct - rightPct),
    disabled = true,
  }
  for _, s in ipairs({
    { title = "Left wider", side = "left", delta = 1 },
    { title = "Left narrower", side = "left", delta = -1 },
    { title = "Right wider", side = "right", delta = 1 },
    { title = "Right narrower", side = "right", delta = -1 },
  }) do
    local _, _, ok = stepped(s.side, s.delta)
    items[#items + 1] = {
      title = s.title,
      disabled = not ok,
      fn = safe(function() M.step(s.side, s.delta) end),
    }
  end
  for _, p in ipairs(M.presets) do
    items[#items + 1] = {
      title = string.format("Left %d%%, right %d%%", p.left, p.right),
      checked = p.left == leftPct and p.right == rightPct,
      fn = safe(function() M.setWidths(p.left, p.right) end),
    }
  end
  return items
end

-- workspaceItems builds the Workspaces folder: a row per saved workspace that
-- opens Recall, the display tie, Replace and Delete, then Save current layout.
local function workspaceItems()
  local frozen, items = paused(), {}
  for _, name in ipairs(workspaces.names()) do
    items[#items + 1] = {
      title = name,
      menu = {
        { title = "Recall", disabled = frozen, fn = safe(function() workspaces.recall(name) end) },
        {
          title = "Recall when these displays connect",
          checked = workspaces.tied(name),
          fn = safe(function() workspaces.tie(name) end),
        },
        { title = "Replace with current layout", fn = safe(function() workspaces.save(name) end) },
        { title = "Delete", fn = safe(function() workspaces.delete(name) end) },
      },
    }
  end
  if #items == 0 then
    items[1] = { title = "No saved workspaces", disabled = true }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = {
    title = "Save current layout…",
    fn = safe(function()
      hs.focus()
      local button, name = hs.dialog.textPrompt("Save workspace",
        "Name this layout of slots, widths and windows.", "", "Save", "Cancel")
      name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
      if button == "Save" and name ~= "" then
        workspaces.save(name)
      end
    end),
  }
  return items
end

-- settingItems builds the Settings folder.
local function settingItems()
  local keymaps, current = {}, M.keymap()
  for _, name in ipairs(actions.keymapNames) do
    keymaps[#keymaps + 1] = {
      title = name:sub(1, 1):upper() .. name:sub(2),
      checked = name == current,
      fn = safe(function() M.setKeymap(name) end),
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
  local front = hs.application.frontmostApplication()
  local frontBundle = front and front:bundleID()
  local ignoreTitle = "Ignore frontmost app"
  if front then
    ignoreTitle = ignoreTitle .. " (" .. (front:name() or frontBundle) .. ")"
  end
  return {
    { title = "Settings window…", fn = safe(settings.open) },
    { title = "-" },
    {
      title = "Fullscreen fills the channel",
      checked = fullscreenFills(),
      fn = safe(function() hs.settings.set(keys.fullscreen, not fullscreenFills()) end),
    },
    {
      title = "Snap by dragging",
      checked = M.snapOn(),
      fn = safe(function() M.setSnap(not M.snapOn()) end),
    },
    { title = "Keymap", menu = keymaps },
    {
      title = ignoreTitle,
      checked = M.shortcutsIgnored(frontBundle),
      disabled = frontBundle == nil or ignoredBundle(frontBundle),
      fn = safe(function() M.toggleShortcutIgnore(frontBundle) end),
    },
    { title = "Icon", menu = icons },
    {
      title = "Edit config",
      fn = safe(function() hs.execute("open -t " .. shellQuote(M.path("anchors.lua"))) end),
    },
    { title = "Console", fn = safe(hs.openConsole) },
  }
end

-- menu builds the menu bar menu from current state: the two layout controls,
-- a folder per job, and Reload.
local function menu()
  local frozen = paused()
  return {
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
    { title = "-" },
    { title = "Window", menu = windowItems() },
    { title = "Locked apps", menu = lockedItems() },
    { title = "Widths", menu = widthItems() },
    { title = "Workspaces", menu = workspaceItems() },
    { title = "Settings", menu = settingItems() },
    { title = "-" },
    { title = "Reload", fn = safe(M.reload) },
  }
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
  local _, problems = M.layout(M.pins())
  for _, problem in ipairs(problems) do
    log(problem)
  end
  actions.attach(M)
  for _, problem in ipairs(actions.bind()) do
    log(problem)
  end
  snap.attach(M, actions)
  tile.attach(M, actions)
  snap.start()
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
  workspaces.attach(M)
  settings.attach(M, actions, workspaces)
  M.screens = hs.screen.watcher.new(safe(function()
    workspaces.screensChanged()
    M.moor()
  end)):start()
  M.timer = hs.timer.doEvery(M.config.pollSeconds, safe(M.moor))
  safe(M.moor)()
  return M
end

return M
