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
  -- expandPct widens a pin while it has focus. A pin holds one window of its app and
  -- leaves the app's other windows free.
  pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left" },
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
  -- icons lists your own menu bar icons for Settings, Icon, Yours. Each has a unique
  -- name and either a glyph of 1 to 5 characters or an image, the full path of a PNG
  -- or SVG file. Images are drawn as template images so they follow the menu bar.
  icons = {},
  -- gapPx is the space in points around and between windows placed by an action.
  gapPx = 0,
  -- leftPct and rightPct are the edge widths until a preset is chosen.
  leftPct = 10,
  rightPct = 45,
  -- leftTopPct and rightTopPct are the share of a strip's height, 10 to 90, its top
  -- row takes when two pins share the side, until one is chosen from Heights.
  leftTopPct = 50,
  rightTopPct = 50,
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

-- heightPresets are the top row heights offered for each side in the menu.
M.heightPresets = { 10, 25, 33, 50, 67, 75, 90 }

-- iconFolders groups the menu bar glyphs offered in the Icon submenu. The first icon stands
-- in when the moorings mark does not load.
M.iconFolders = {
  {
    name = "Boats",
    icons = {
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
    },
  },
  {
    name = "Sea life",
    icons = {
      { name = "Wave", glyph = "🌊" },
      { name = "Octopus", glyph = "🐙" },
      { name = "Crab", glyph = "🦀" },
      { name = "Turtle", glyph = "🐢" },
      { name = "Whale", glyph = "🐳" },
      { name = "Dolphin", glyph = "🐬" },
      { name = "Fish", glyph = "🐟" },
      { name = "Tropical fish", glyph = "🐠" },
      { name = "Shark", glyph = "🦈" },
      { name = "Seal", glyph = "🦭" },
      { name = "Shrimp", glyph = "🦐" },
      { name = "Lobster", glyph = "🦞" },
      { name = "Squid", glyph = "🦑" },
      { name = "Jellyfish", glyph = "🪼" },
      { name = "Coral", glyph = "🪸" },
      { name = "Shell", glyph = "🐚" },
      { name = "Penguin", glyph = "🐧" },
    },
  },
  {
    name = "Tools",
    icons = {
      { name = "Ladder", glyph = "🪜" },
      { name = "Pushpin", glyph = "📌" },
      { name = "Wrench", glyph = "🔧" },
      { name = "Hammer", glyph = "🔨" },
      { name = "Gear", glyph = "⚙️" },
      { name = "Link", glyph = "🔗" },
      { name = "Magnet", glyph = "🧲" },
      { name = "Toolbox", glyph = "🧰" },
      { name = "Window", glyph = "🪟" },
      { name = "Rocket", glyph = "🚀" },
    },
  },
  {
    name = "Hearts and shapes",
    icons = {
      { name = "Orange heart", glyph = "🧡" },
      { name = "Blue heart", glyph = "💙" },
      { name = "Black heart", glyph = "🖤" },
      { name = "White heart", glyph = "🤍" },
      { name = "Orange circle", glyph = "🟠" },
      { name = "Black circle", glyph = "⚫" },
      { name = "Orange square", glyph = "🟧" },
      { name = "Diamond", glyph = "🔶" },
      { name = "Star", glyph = "⭐" },
      { name = "Sparkles", glyph = "✨" },
      { name = "Lightning", glyph = "⚡" },
      { name = "Sun", glyph = "☀️" },
      { name = "Moon", glyph = "🌙" },
    },
  },
}

-- icons is every built-in glyph in folder order.
M.icons = {}
for _, folder in ipairs(M.iconFolders) do
  for _, icon in ipairs(folder.icons) do
    M.icons[#M.icons + 1] = icon
  end
end

-- maxIconChars is the longest custom icon text, counted in code points.
local maxIconChars = 5

local keys = {
  widths = "moorings.widths",
  heights = "moorings.heights",
  icon = "moorings.icon",
  customIcon = "moorings.customIcon",
  paused = "moorings.paused",
  fullscreen = "moorings.fullscreenFills",
  pinFullscreen = "moorings.pinFullscreenFills",
  slots = "moorings.slots",
  ignoreShortcuts = "moorings.ignoreShortcuts",
  snap = "moorings.snap",
  hammerspoonUpdates = "moorings.hammerspoonUpdates",
  keymap = "moorings.keymap",
  shortcuts = "moorings.shortcuts",
  sizes = "moorings.sizes",
  gap = "moorings.gapPx",
}

-- minChannelPct is the narrowest channel a width pair may leave.
local minChannelPct = 10

-- minRowPct is the shortest share of a strip's height either row may take.
local minRowPct = 10

-- heightStep is how many points Taller and Shorter move a top row.
local heightStep = 5

-- burstMoves moves of one window inside burstSeconds put it on hold for holdSeconds.
local burstMoves, burstSeconds, holdSeconds = 4, 10, 60

-- releaseGrace is how many seconds after a move a pin may settle on its own before a
-- change is taken as the owner moving it.
local releaseGrace = 2

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
  -- axMissing is set while Accessibility is known to be missing.
  axMissing = false,
  -- axNotice is the notification shown the first time Accessibility is missing.
  axNotice = nil,
  -- clamped maps a window id to the width it had before the channel narrowed it.
  clamped = {},
  -- floors maps a window id to the smallest width and height it was seen to keep.
  floors = {},
  -- minPts holds the widest floor among the pinned windows on each side.
  minPts = { left = 0, right = 0 },
  -- minBy names the app whose floor sets minPts on each side.
  minBy = {},
  -- placed maps a pinned window id to its target, the frame moorings left it at, and when.
  placed = {},
  -- released holds the pinned window ids the owner moved, which moorings leaves alone.
  released = {},
  -- lifted holds the pinned window ids lifted over their strip and the channel.
  lifted = {},
  -- zoom maps a pinned window id to its frame and the green button rect at that frame.
  zoom = {},
  -- holders maps a pinned bundle ID to the id of the one window the pin holds.
  holders = {},
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

-- fit grows frame to the smallest size the window with id is known to keep. The edges
-- named in anchor stay put: right keeps the right edge and bottom the bottom edge.
local function fit(id, frame, anchor)
  local fl = state.floors[id]
  if not fl then
    return frame
  end
  local f = rect(frame)
  anchor = anchor or {}
  if fl.w > f.w then
    if anchor.right then
      f.x = f.x + f.w - fl.w
    end
    f.w = fl.w
  end
  if fl.h > f.h then
    if anchor.bottom then
      f.y = f.y + f.h - fl.h
    end
    f.h = fl.h
  end
  return f
end

-- learn records when win kept a larger size than frame, the move it was just given,
-- and moves it once more so the edges in anchor line up with target.
local function learn(win, target, frame, anchor)
  local got, t = win:frame(), M.config.tolerance
  if got.w <= frame.w + t and got.h <= frame.h + t then
    return
  end
  local id = win:id()
  local fl = { w = math.max(got.w, frame.w), h = math.max(got.h, frame.h) }
  state.floors[id] = fl
  log(string.format("window %s keeps a size of at least %.0fx%.0f: leaving it that size",
    tostring(id), fl.w, fl.h))
  local want = fit(id, target, anchor)
  if not near(got, want) then
    win:setFrame(want)
  end
end

-- place moves win to frame unless it is already there, keeping the size of a window that
-- will not shrink to fit, against the edges in anchor. A window that keeps moving away
-- from the same frame is left alone for holdSeconds.
local function place(win, frame, anchor)
  local id, t, target = win:id(), M.now(), frame
  frame = fit(id, frame, anchor)
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
  learn(win, target, frame, anchor)
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

-- hammerspoonUpdates reports whether moorings keeps Hammerspoon updating itself, on unless
-- the owner turned it off.
function M.hammerspoonUpdates()
  return hs.settings.get(keys.hammerspoonUpdates) ~= false
end

-- applyHammerspoonUpdates tells Hammerspoon's updater, Sparkle, to check on its own and,
-- while the setting is on, to download updates quietly and install them when Hammerspoon
-- next quits. Turned off, Sparkle goes back to asking before it installs.
local function applyHammerspoonUpdates()
  local on = M.hammerspoonUpdates()
  hs.settings.set("SUEnableAutomaticChecks", true)
  hs.settings.set("SUAutomaticallyUpdate", on)
  if hs.automaticallyCheckForUpdates then
    pcall(hs.automaticallyCheckForUpdates, true)
  end
end

-- setHammerspoonUpdates turns quiet Hammerspoon updates on or off and applies the choice.
function M.setHammerspoonUpdates(on)
  hs.settings.set(keys.hammerspoonUpdates, on == true)
  applyHammerspoonUpdates()
end

-- fullscreenFills reports whether native fullscreen is redirected to the channel.
local function fullscreenFills()
  return hs.settings.get(keys.fullscreen) ~= false
end

-- pinFullscreenFills reports whether native fullscreen on a pinned window is
-- redirected back to its slot.
local function pinFullscreenFills()
  return hs.settings.get(keys.pinFullscreen) ~= false
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

-- held reports whether an app that will not shrink holds side wider than pct on screen s.
local function held(s, side, pct)
  return s ~= nil and state.minPts[side] > math.floor(s:frame().w * pct / 100)
end

-- stepped returns the widths after moving side by delta points, and whether
-- they still leave a usable channel and do not narrow a side an app holds wider.
local function stepped(side, delta)
  local left, right = M.widths()
  if side == "left" then
    left = left + delta
  else
    right = right + delta
  end
  local narrowHeld = delta < 0 and held(M.ultrawide(), side, side == "left" and left or right)
  return left, right, validSplit(left, right) and not narrowHeld
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

-- validTop reports whether pct leaves both rows of a strip at least minRowPct tall.
local function validTop(pct)
  return type(pct) == "number" and pct >= minRowPct and pct <= 100 - minRowPct
end

-- heights returns the left and right top row percentages in effect. A height
-- chosen from the menu wins over the config, side by side.
function M.heights()
  local saved = hs.settings.get(keys.heights)
  saved = type(saved) == "table" and saved or {}
  local out = {}
  for _, side in ipairs({ "left", "right" }) do
    local configured = M.config[side .. "TopPct"]
    if validTop(saved[side]) then
      out[side] = saved[side]
    elseif validTop(configured) then
      out[side] = configured
    else
      if configured ~= nil then
        log(side .. "TopPct must be a number from 10 to 90: using 50")
      end
      out[side] = 50
    end
  end
  return out.left, out.right
end

-- setHeights saves left and right as the top row heights and re-moors.
function M.setHeights(left, right)
  hs.settings.set(keys.heights, { left = left, right = right })
  M.moor()
end

-- setTop saves pct as the top row height of side, keeping the other side, and re-moors.
function M.setTop(side, pct)
  local left, right = M.heights()
  if side == "left" then
    M.setHeights(pct, right)
  else
    M.setHeights(left, pct)
  end
end

-- topStepped returns side's top row height after moving it by delta points, and
-- whether both rows stay at least minRowPct tall.
local function topStepped(side, delta)
  local left, right = M.heights()
  local pct = (side == "left" and left or right) + delta
  return pct, validTop(pct)
end

-- stepTop makes side's top row taller or shorter by delta points, refusing a
-- step that would leave either row under minRowPct.
function M.stepTop(side, delta)
  local pct, ok = topStepped(side, delta)
  if ok then
    M.setTop(side, pct)
  end
  return ok
end

-- The frame math lives in geometry, re-exported here for callers and tests.
M.edge, M.slot, M.regions, M.clamp = geometry.edge, geometry.slot, geometry.regions, geometry.clamp
M.lift = geometry.lift

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

-- anchoredSides reports which sides hold at least one anchored app, running or not.
local function anchoredSides()
  local picks = M.assignments()
  return {
    left = picks["left-top"] ~= "" or picks["left-bottom"] ~= "",
    right = picks["right-top"] ~= "" or picks["right-bottom"] ~= "",
  }
end

-- inUse returns the left and right widths in use on frame f: the chosen widths, grown to
-- fit the widest pin on each side that will not shrink, while the channel keeps at least
-- minChannelPct. A side with no anchored app is 0 wide, so the channel takes it over.
function M.inUse(f)
  local left, right = M.widths()
  local sides = anchoredSides()
  left, right = sides.left and left or 0, sides.right and right or 0
  local grow = {}
  for side, pct in pairs({ left = left, right = right }) do
    grow[side] = sides[side] and math.max(0, (state.minPts[side] + 0.5) * 100 / f.w - pct) or 0
  end
  local room, total = 100 - minChannelPct - left - right, grow.left + grow.right
  if total > room then
    grow.left, grow.right = grow.left * room / total, grow.right * room / total
  end
  return left + grow.left, right + grow.right
end

-- channel returns the channel frame on screen s.
function M.channel(s)
  return M.regions(s:frame(), M.inUse(s:frame())).channel
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

-- validRow reports whether row names a row of a strip.
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
-- chosen app keeps the expandPct the config gives it.
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
      list[#list + 1] = { bundle = bundle, side = s.side, row = s.row, expandPct = base.expandPct }
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

-- clearSlots empties every slot and saves the result, so no app is anchored until one is
-- picked again.
function M.clearSlots()
  local picks = {}
  for _, s in ipairs(M.slotNames) do
    picks[s.key] = ""
  end
  hs.settings.set(keys.slots, picks)
  M.moor()
end

-- lock puts bundle in the slot named key and opens the app the way a Dock click
-- does, which launches it or asks a running app with no window for a new one.
function M.lock(key, bundle)
  M.assign(key, bundle)
  if bundle ~= "" then
    hs.task.new("/usr/bin/open", nil, { "-b", bundle }):start()
  end
end

-- assignPath locks the app at path in the slot named key, or returns nil and a
-- reason when path is not an app moorings may lock.
function M.assignPath(key, path)
  local info = type(path) == "string" and hs.application.infoForBundlePath(path)
  local bundle = type(info) == "table" and info.CFBundleIdentifier
  if type(bundle) ~= "string" or bundle == "" then
    return nil, tostring(path) .. " is not an app with a bundle ID"
  end
  if ignoredBundle(bundle) then
    return nil, bundle .. " is in ignoreBundles"
  end
  M.lock(key, bundle)
  return true
end

-- chooseApp asks for an app in a file browser and puts it in the slot named key.
function M.chooseApp(key)
  hs.focus()
  local picked = hs.dialog.chooseFileOrFolder("Choose an app to anchor", "/Applications",
    true, false, false, { "app" }, true)
  local path = picked and picked["1"]
  if not path then
    return
  end
  local ok, problem = M.assignPath(key, path)
  if not ok then
    hs.alert.show(problem)
  end
end

-- resetSlots drops the switcher choices so the config is in effect again.
function M.resetSlots()
  hs.settings.clear(keys.slots)
  M.moor()
end

-- slotFrame returns the frame of the slot named key, such as left-top, on
-- screen s at the side's current width and height.
function M.slotFrame(s, key)
  local side, row = key:match("^(%a+)-(%a+)$")
  local leftPct, rightPct = M.inUse(s:frame())
  local chosenLeft, chosenRight = M.widths()
  leftPct = leftPct > 0 and leftPct or chosenLeft
  rightPct = rightPct > 0 and rightPct or chosenRight
  local leftTop, rightTop = M.heights()
  if side == "left" then
    return M.slot(s:frame(), side, row, leftPct, leftTop)
  end
  return M.slot(s:frame(), side, row, rightPct, rightTop)
end

-- slotFor returns the slot of win's app, or nil when the app is not pinned.
function M.slotFor(win)
  local slots = M.layout(M.pins())
  return slots[bundleOf(win)]
end

-- pinsWindow reports whether pin holds win. A pin holds one window: the one it already
-- holds, or else the app's main window, which it then keeps.
local function pinsWindow(pin, win)
  local held = state.holders[pin.bundle]
  if held then
    return held == win:id()
  end
  local main = win:application():mainWindow()
  if main ~= nil and main:id() == win:id() then
    state.holders[pin.bundle] = win:id()
    return true
  end
  return false
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

-- accessChanged reacts when Accessibility goes missing or comes back. It is set
-- with the menu bar code below.
local accessChanged

-- trusted reports whether Accessibility is granted, logging once when it is not,
-- and calls accessChanged when the answer flips.
local function trusted()
  if hs.accessibilityState() then
    state.axWarned = false
    if state.axMissing then
      state.axMissing = false
      accessChanged(true)
    end
    return true
  end
  if not state.axWarned then
    print("moorings: Accessibility is not granted: windows will not move")
    state.axWarned = true
  end
  if not state.axMissing then
    state.axMissing = true
    accessChanged(false)
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

-- setLayout saves slots, the strip widths and the top row heights without
-- re-mooring. A value that is missing or out of bounds is skipped.
function M.setLayout(slots, left, right, heights)
  if type(slots) == "table" then
    hs.settings.set(keys.slots, slots)
  end
  if validSplit(left, right) then
    hs.settings.set(keys.widths, { left = left, right = right })
  end
  if type(heights) == "table" and validTop(heights.left) and validTop(heights.right) then
    hs.settings.set(keys.heights, { left = heights.left, right = heights.right })
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

-- toggleLift lifts pinned window win over its strip and the channel, or lowers it back
-- into its slot, and reports whether win is a pin.
function M.toggleLift(win)
  if not win or not M.pinned(win) then
    return false
  end
  local id = win:id()
  local up = not state.lifted[id]
  state.lifted[id], state.released[id], state.placed[id] = up or nil, nil, nil
  if up then
    win:focus()
  end
  M.moor()
  return true
end

-- remoor puts a released or lifted pin back in its slot.
function M.remoor(win)
  local id = win:id()
  state.lifted[id], state.released[id], state.placed[id] = nil, nil, nil
  M.moor()
  return true
end

-- zoomClick lifts or lowers the pin whose green button holds point p, or re-moors it when
-- it was released, and reports whether it did, so the click can be kept from starting native
-- fullscreen. The work runs after the event so the mouse tap never waits on a window.
function M.zoomClick(p)
  if not p or paused() then
    return false
  end
  for id, c in pairs(state.zoom) do
    local r = c.rect
    if r and p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h then
      hs.timer.doAfter(0, safe(function()
        local win = hs.window.get(id)
        if win and state.released[id] then
          M.remoor(win)
        else
          M.toggleLift(win)
        end
      end))
      return true
    end
  end
  return false
end

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

-- windowApp returns the name of win's app, or its bundle ID when it has no name.
local function windowApp(win)
  local app = win:application()
  local name = app and app.name and app:name()
  return name or bundleOf(win) or "an app"
end

-- measure records the widest floor among the pinned windows on each side in wins.
local function measure(wins, slots)
  local mins, by = { left = 0, right = 0 }, {}
  for _, w in ipairs(wins) do
    local slot = slots[bundleOf(w)]
    local fl = slot and state.floors[w:id()]
    if fl and fl.w > mins[slot.side] then
      mins[slot.side], by[slot.side] = fl.w, windowApp(w)
    end
  end
  state.minPts, state.minBy = mins, by
end

-- cacheZoom keeps the green button rect of pinned window w at frame f, asking the window
-- only when the frame changed.
local function cacheZoom(w, f)
  local id = w:id()
  local c = state.zoom[id]
  if c and near(c.frame, f) then
    return
  end
  local ok, r = pcall(function() return w.zoomButtonRect and w:zoomButtonRect() end)
  state.zoom[id] = { frame = rect(f), rect = ok and r and rect(r) or nil }
end

-- release leaves pinned window w where the owner put it and says how to re-moor it.
local function release(w)
  local id, name = w:id(), windowApp(w)
  state.released[id], state.lifted[id] = true, nil
  local sc = actions.bindings().restore
  local how = sc and (", press " .. actions.keyText(sc) .. ",") or ""
  log("window " .. tostring(id) .. " was moved by hand: released")
  hs.alert.show(string.format("%s released: moorings leaves it where you put it. "
    .. "To re-moor it, click its green button%s or choose Re-moor %s in the moorings menu.",
    name, how, name), 4)
end

-- moorPin places pinned window w at target, or releases it when the owner has moved it
-- since moorings last left it.
local function moorPin(w, target, anchor)
  local id, t = w:id(), M.now()
  local last = state.placed[id]
  local moved = last and t - last.t > releaseGrace and not near(w:frame(), last.at)
  if moved and not state.released[id] then
    release(w)
  end
  if state.released[id] then
    cacheZoom(w, w:frame())
    return
  end
  place(w, target, anchor)
  local at = w:frame()
  if not last or not near(last.at, at) or not near(last.target, target) then
    state.placed[id] = { target = rect(target), at = rect(at), t = t }
  end
  cacheZoom(w, at)
end

-- moor puts every pin on its edge and every free window in the channel.
function M.moor()
  local granted = trusted()
  if paused() or mouseHeld() or not granted then
    return
  end
  local s = M.ultrawide()
  if not s then
    return
  end
  local frame = s:frame()
  local slots = M.layout(M.pins())
  local all = windows()
  measure(all, slots)
  local leftPct, rightPct = M.inUse(frame)
  local pct = { left = leftPct, right = rightPct }
  local leftTop, rightTop = M.heights()
  local topPct = { left = leftTop, right = rightTop }
  local ch = M.regions(frame, leftPct, rightPct).channel
  local lift = {
    left = M.lift(frame, "left", leftPct, rightPct),
    right = M.lift(frame, "right", leftPct, rightPct),
  }
  local focused = hs.window.focusedWindow()
  local focusedSlot = focused and slots[bundleOf(focused)]
  local t, seen = M.now(), {}
  for _, w in ipairs(all) do
    local slot = slots[bundleOf(w)]
    seen[w:id()] = true
    if slot then
      local id = w:id()
      if pinsWindow(slot.pin, w) and w:isFullScreen() then
        local started = state.pendingFill[id]
        if pinFullscreenFills() and not (started and t - started <= pendingSeconds) then
          state.pendingFill[id] = t
          w:setFullScreen(false)
        end
      elseif pinsWindow(slot.pin, w) then
        state.pendingFill[id] = nil
        local width = (slot == focusedSlot and slot.pin.expandPct) or pct[slot.side]
        local target = state.lifted[id] and lift[slot.side]
          or M.slot(frame, slot.side, slot.row, width, topPct[slot.side])
        moorPin(w, target, { right = slot.side == "right", bottom = slot.row == "bottom" })
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
  for _, tbl in ipairs({ state.clamped, state.bursts, state.pendingFill, state.floors,
    state.placed, state.released, state.lifted, state.zoom }) do
    for id in pairs(tbl) do
      if not seen[id] then
        tbl[id] = nil
      end
    end
  end
  for bundle, id in pairs(state.holders) do
    if not seen[id] then
      state.holders[bundle] = nil
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

-- M.validIcon trims text and returns it when it is 1 to 5 code points, else nil and a reason.
function M.validIcon(text)
  if type(text) ~= "string" then
    return nil, "Enter 1 to " .. maxIconChars .. " characters."
  end
  text = text:match("^%s*(.-)%s*$")
  local n = utf8.len(text)
  if n == nil or n < 1 or n > maxIconChars then
    return nil, "Enter 1 to " .. maxIconChars .. " characters."
  end
  return text
end

-- imageExts lists the file extensions loaded as image icons.
local imageExts = { png = true, svg = true, pdf = true, jpg = true, jpeg = true }

-- iconSize is the width and height in points of an image icon in the menu bar.
local iconSize = 18

-- axGlyph replaces the menu bar icon while Accessibility is missing.
local axGlyph = "⚠️"

-- axPane is the System Settings page that grants Accessibility.
local axPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

-- M.random picks an integer from 1 to n. Tests replace it.
M.random = math.random

-- M.iconDir returns the folder of image icons. moorings never creates it.
function M.iconDir()
  return M.path("icons")
end

-- M.imageIcons lists the image files in the icon folder, sorted by name.
function M.imageIcons()
  local dir = M.iconDir()
  if hs.fs.attributes(dir, "mode") ~= "directory" then
    return {}
  end
  local ok, iter, obj = pcall(hs.fs.dir, dir)
  if not ok then
    log(iter)
    return {}
  end
  local list = {}
  for file in iter, obj do
    local base, ext = file:match("^([^.].*)%.(%w+)$")
    if base and imageExts[ext:lower()] then
      list[#list + 1] = { name = "image:" .. file, title = base, image = dir .. "/" .. file }
    end
  end
  table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
  return list
end

-- markIcon returns the moorings mark, a template image shipped with moorings.
local function markIcon()
  return { name = "moorings mark", title = "moorings mark", image = M.path("mark.svg") }
end

-- M.configIcons returns the valid entries of the config icon list. A bad entry is
-- logged and skipped.
function M.configIcons()
  local list, seen = {}, { [markIcon().name] = true }
  for _, icon in ipairs(M.icons) do
    seen[icon.name] = true
  end
  local entries = type(M.config.icons) == "table" and M.config.icons or {}
  for i, e in ipairs(entries) do
    local named = type(e) == "table" and type(e.name) == "string" and e.name ~= ""
      and not e.name:find("^image:") and not seen[e.name]
    local glyph = named and e.glyph ~= nil and e.image == nil and M.validIcon(e.glyph)
    local image = named and e.glyph == nil and type(e.image) == "string" and e.image ~= "" and e.image
    if glyph or image then
      seen[e.name] = true
      list[#list + 1] = { name = e.name, title = e.name, glyph = glyph or nil, image = image or nil }
    else
      log("icons entry " .. i .. " is skipped: it needs a unique name and a glyph or an image")
    end
  end
  return list
end

-- findIcon returns the built-in, mark, config or image icon called name, or nil.
local function findIcon(name)
  for _, icon in ipairs(M.icons) do
    if icon.name == name then
      return icon
    end
  end
  if name == markIcon().name then
    return markIcon()
  end
  for _, icon in ipairs(M.configIcons()) do
    if icon.name == name then
      return icon
    end
  end
  for _, icon in ipairs(M.imageIcons()) do
    if icon.name == name then
      return icon
    end
  end
  return nil
end

-- fallbackIcon returns the default icon, its name and its loaded image: the moorings mark,
-- or the first built-in glyph when the mark does not load.
local function fallbackIcon()
  local mark = markIcon()
  local img = hs.image.imageFromPath(mark.image)
  if img then
    return mark, mark.name, img
  end
  if not state.markWarned then
    log("icon image " .. mark.image .. " did not load: using " .. M.icons[1].name)
    state.markWarned = true
  end
  return M.icons[1], M.icons[1].name
end

-- currentIcon returns the icon in effect, its name, which is nil for custom text, and
-- the loaded image of an image icon. A missing or unknown choice, or an image that does
-- not load, gives the default icon.
local function currentIcon()
  local custom = M.validIcon(hs.settings.get(keys.customIcon))
  if custom then
    return { glyph = custom }, nil
  end
  local found = findIcon(hs.settings.get(keys.icon))
  if found and found.image then
    local img = hs.image.imageFromPath(found.image)
    if img then
      return found, found.name, img
    end
    log("icon image " .. found.image .. " did not load: using the default icon")
  elseif found then
    return found, found.name
  end
  return fallbackIcon()
end

-- applyIcon puts the icon in effect on the menu bar.
local function applyIcon()
  if not M.bar then
    return
  end
  if state.axMissing then
    M.bar:setIcon(nil)
    M.bar:setTitle(axGlyph)
    return
  end
  local icon, _, img = currentIcon()
  if img then
    img = img:setSize({ w = iconSize, h = iconSize })
    img:template(true)
    M.bar:setIcon(img, true)
    M.bar:setTitle(nil)
    return
  end
  M.bar:setIcon(nil)
  M.bar:setTitle(icon.glyph)
end

-- assign saves v under key, or clears the key when v is nil.
local function assign(key, v)
  if v == nil then
    hs.settings.clear(key)
  else
    hs.settings.set(key, v)
  end
end

-- setChoice saves the icon name and custom text, remembers the previous choice for
-- undo and applies the result. A choice equal to the saved one changes nothing.
local function setChoice(icon, custom)
  if icon == hs.settings.get(keys.icon) and custom == hs.settings.get(keys.customIcon) then
    return
  end
  state.prevIcon = { icon = hs.settings.get(keys.icon), custom = hs.settings.get(keys.customIcon) }
  assign(keys.icon, icon)
  assign(keys.customIcon, custom)
  applyIcon()
end

-- M.pickIcon chooses the icon called name, or returns nil and a reason.
function M.pickIcon(name)
  if not findIcon(name) then
    return nil, "That icon is not available."
  end
  setChoice(name, nil)
  return true
end

-- M.setCustomIcon chooses custom text, or returns nil and a reason.
function M.setCustomIcon(text)
  local valid, problem = M.validIcon(text)
  if not valid then
    return nil, problem
  end
  setChoice(nil, valid)
  return true
end

-- M.defaultIcon returns to the default icon.
function M.defaultIcon()
  setChoice(nil, nil)
  return true
end

-- M.surpriseIcon picks a built-in icon other than the current one at random.
function M.surpriseIcon()
  local _, current = currentIcon()
  local pool = {}
  for _, icon in ipairs(M.icons) do
    if icon.name ~= current then
      pool[#pool + 1] = icon
    end
  end
  setChoice(pool[M.random(#pool)].name, nil)
  return true
end

-- M.undoIcon restores the choice made before the last change, or returns nil and a reason.
function M.undoIcon()
  local prev = state.prevIcon
  if not prev then
    return nil, "There is no icon change to undo."
  end
  setChoice(prev.icon, prev.custom)
  return true
end

-- M.openAccessibility opens the System Settings page that grants Accessibility.
function M.openAccessibility()
  hs.execute("open " .. shellQuote(axPane))
end

-- accessChanged shows the warning glyph and one notification when Accessibility
-- goes missing. When it comes back it clears both and binds the shortcuts and
-- the drag watcher again, since ones made before the grant may not receive events.
accessChanged = function(granted)
  applyIcon()
  if not granted then
    if not state.axNotice then
      state.axNotice = hs.notify.new(function() M.openAccessibility() end, {
        title = "moorings needs Accessibility",
        informativeText = "Windows will not move until Hammerspoon is allowed under "
          .. "Privacy & Security, Accessibility.",
        actionButtonTitle = "Open Settings",
        hasActionButton = true,
        withdrawAfter = 0,
      }):send()
    end
    return
  end
  if state.axNotice then
    state.axNotice:withdraw()
  end
  if not M.bar then
    return
  end
  for _, problem in ipairs(actions.bind()) do
    log(problem)
  end
  snap.start()
  hs.alert.show("moorings: Accessibility granted")
end

-- M.openIconDir reveals the icon folder, or says how to create it.
function M.openIconDir()
  local dir = M.iconDir()
  if hs.fs.attributes(dir, "mode") == "directory" then
    hs.execute("open " .. shellQuote(dir))
  else
    hs.alert.show("Create " .. dir .. " and add PNG or SVG files, then reopen the menu.")
  end
end

-- M.iconModel describes every icon choice and the current one, for the menu and the
-- settings window.
function M.iconModel()
  local _, name = currentIcon()
  local custom = M.validIcon(hs.settings.get(keys.customIcon))
  local groups = {}
  for _, g in ipairs(M.iconFolders) do
    local icons = {}
    for _, icon in ipairs(g.icons) do
      icons[#icons + 1] = { name = icon.name, title = icon.name, glyph = icon.glyph,
        checked = icon.name == name }
    end
    groups[#groups + 1] = { title = g.name, icons = icons }
  end
  local yours = {}
  for _, list in ipairs({ M.configIcons(), M.imageIcons() }) do
    for _, icon in ipairs(list) do
      yours[#yours + 1] = { name = icon.name, title = icon.title, glyph = icon.glyph,
        image = icon.image ~= nil, checked = icon.name == name }
    end
  end
  local mark = markIcon()
  return {
    mark = { name = mark.name, title = mark.title, image = true, checked = mark.name == name },
    groups = groups,
    yours = yours,
    custom = custom or "",
    usingCustom = custom ~= nil,
    canUndo = state.prevIcon ~= nil,
  }
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
-- of running apps and a file browser, a fast path for the frontmost app, and a reset.
local function lockedItems()
  local picks, apps = M.assignments(), runningApps()
  local running = {}
  for _, app in ipairs(apps) do
    running[app.bundle] = true
  end
  local items = {}
  for _, s in ipairs(M.slotNames) do
    local current = picks[s.key]
    local choices = {
      {
        title = "Empty",
        tooltip = "Leave this slot free and open nothing.",
        checked = current == "",
        fn = safe(function() M.assign(s.key, "") end),
      },
    }
    if current ~= "" and not running[current] then
      choices[#choices + 1] = {
        title = appName(current),
        tooltip = "Anchored here but not running. Its first window will take the slot.",
        checked = true,
      }
    end
    for _, app in ipairs(apps) do
      choices[#choices + 1] = {
        title = app.name,
        tooltip = "Anchor this app to the slot and bring its window there.",
        checked = app.bundle == current,
        fn = safe(function() M.lock(s.key, app.bundle) end),
      }
    end
    choices[#choices + 1] = { title = "-" }
    choices[#choices + 1] = {
      title = "Choose app…",
      tooltip = "Pick any app in Applications, running or not, and open it in this slot.",
      fn = safe(function() M.chooseApp(s.key) end),
    }
    items[#items + 1] = { title = s.title .. ": " .. appName(current), menu = choices }
  end
  local front = hs.application.frontmostApplication()
  local frontBundle = front and front:bundleID()
  local targets = {}
  for _, s in ipairs(M.slotNames) do
    targets[#targets + 1] = {
      title = s.title,
      tooltip = "Anchor the frontmost app to this slot.",
      checked = picks[s.key] == frontBundle,
      fn = safe(function() M.assign(s.key, frontBundle) end),
    }
  end
  local pinTitle = "Anchor frontmost app"
  if front then
    pinTitle = pinTitle .. " (" .. (front:name() or frontBundle) .. ")"
  end
  items[#items + 1] = {
    title = pinTitle,
    disabled = ignoredBundle(frontBundle),
    menu = targets,
  }
  local anchored = false
  for _, bundle in pairs(picks) do
    anchored = anchored or bundle ~= ""
  end
  items[#items + 1] = {
    title = "Unanchor all apps",
    tooltip = "Empty every slot so no app is held. Raise anchor pauses instead.",
    disabled = not anchored,
    fn = safe(M.clearSlots),
  }
  items[#items + 1] = {
    title = "Reset to defaults",
    tooltip = "Go back to the slots in the config.",
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
    {
      title = "Fill channel",
      tooltip = "Stretch the front free window across the whole channel.",
      disabled = frozen,
      fn = safe(M.fill),
    },
    {
      title = "Tidy channel",
      disabled = frozen,
      menu = {
        {
          title = "Halves",
          tooltip = "Tile the two front free windows side by side.",
          fn = safe(function() M.tidy(2) end),
        },
        {
          title = "Thirds",
          tooltip = "Tile the three front free windows side by side.",
          fn = safe(function() M.tidy(3) end),
        },
      },
    },
    {
      title = "Undo tidy",
      tooltip = "Put back every window Fill or Tidy moved.",
      fn = safe(M.undo),
      disabled = frozen or not M.canUndo(),
    },
  })
end

-- widthItems builds the Widths folder: the channel label, the steppers and
-- the presets.
local function widthItems()
  local items = {}
  local leftPct, rightPct = M.widths()
  local s = M.ultrawide()
  local useLeft, useRight = leftPct, rightPct
  if s then
    useLeft, useRight = M.inUse(s:frame())
  end
  items[#items + 1] = {
    title = string.format("Channel %.0f%%", 100 - useLeft - useRight),
    tooltip = "The share of the display left between the strips for free windows.",
    disabled = true,
  }
  for _, h in ipairs({ { "left", "Left", leftPct }, { "right", "Right", rightPct } }) do
    local side, name, chosen = h[1], h[2], h[3]
    if s and held(s, side, chosen) then
      items[#items + 1] = {
        title = string.format("%s %.0f%% in use: %s needs %.0f pt", name,
          side == "left" and useLeft or useRight, state.minBy[side] or "an app", state.minPts[side]),
        tooltip = "An anchored window will not go narrower, so the strip grows to fit it.",
        disabled = true,
      }
    end
  end
  local sides = anchoredSides()
  for _, h in ipairs({ { "left", "Left" }, { "right", "Right" } }) do
    if not sides[h[1]] then
      items[#items + 1] = {
        title = h[2] .. " side empty: part of the channel",
        tooltip = "Nothing is anchored on this side, so free windows use it until an app is.",
        disabled = true,
      }
    end
  end
  for _, s in ipairs({
    { title = "Left wider", side = "left", delta = 1 },
    { title = "Left narrower", side = "left", delta = -1 },
    { title = "Right wider", side = "right", delta = 1 },
    { title = "Right narrower", side = "right", delta = -1 },
  }) do
    local _, _, ok = stepped(s.side, s.delta)
    items[#items + 1] = {
      title = s.title,
      tooltip = "Move the strip's inner edge by one percent of the display.",
      disabled = not ok,
      fn = safe(function() M.step(s.side, s.delta) end),
    }
  end
  for _, p in ipairs(M.presets) do
    items[#items + 1] = {
      title = string.format("Left %d%%, right %d%%", p.left, p.right),
      tooltip = "Set both strips to these shares of the display.",
      checked = p.left == leftPct and p.right == rightPct,
      disabled = held(s, "left", p.left) or held(s, "right", p.right),
      fn = safe(function() M.setWidths(p.left, p.right) end),
    }
  end
  return items
end

-- heightItems builds the Heights folder: a label per side, the taller and shorter
-- steppers, and a folder of presets per side.
local function heightItems()
  local items = {}
  local leftTop, rightTop = M.heights()
  local current = { left = leftTop, right = rightTop }
  local sides = { { side = "left", name = "Left" }, { side = "right", name = "Right" } }
  for _, s in ipairs(sides) do
    local top = current[s.side]
    items[#items + 1] = {
      title = string.format("%s top %g%%, bottom %g%%", s.name, top, 100 - top),
      tooltip = "How this strip's height splits between its two rows.",
      disabled = true,
    }
  end
  for _, s in ipairs({
    { title = "Left top taller", side = "left", delta = heightStep },
    { title = "Left top shorter", side = "left", delta = -heightStep },
    { title = "Right top taller", side = "right", delta = heightStep },
    { title = "Right top shorter", side = "right", delta = -heightStep },
  }) do
    local _, ok = topStepped(s.side, s.delta)
    items[#items + 1] = {
      title = s.title,
      tooltip = "Move the line between the top and bottom rows by " .. heightStep .. " percent.",
      disabled = not ok,
      fn = safe(function() M.stepTop(s.side, s.delta) end),
    }
  end
  for _, s in ipairs(sides) do
    local presets = {}
    for _, pct in ipairs(M.heightPresets) do
      presets[#presets + 1] = {
        title = string.format("Top %d%%, bottom %d%%", pct, 100 - pct),
        tooltip = "Split this strip's height between its rows at these shares.",
        checked = pct == current[s.side],
        fn = safe(function() M.setTop(s.side, pct) end),
      }
    end
    items[#items + 1] = { title = s.name .. " side", menu = presets }
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
        {
          title = "Recall",
          tooltip = "Put the slots, widths, heights and windows back as saved.",
          disabled = frozen,
          fn = safe(function() workspaces.recall(name) end),
        },
        {
          title = "Recall when these displays connect",
          tooltip = "Bring this workspace back whenever the displays attached now are plugged in.",
          checked = workspaces.tied(name),
          fn = safe(function() workspaces.tie(name) end),
        },
        {
          title = "Replace with current layout",
          tooltip = "Save the layout in effect now under this name.",
          fn = safe(function() workspaces.save(name) end),
        },
        {
          title = "Delete",
          tooltip = "Forget this workspace.",
          fn = safe(function() workspaces.delete(name) end),
        },
      },
    }
  end
  if #items == 0 then
    items[1] = {
      title = "No saved workspaces",
      tooltip = "Save the current layout to recall it later.",
      disabled = true,
    }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = {
    title = "Save current layout…",
    tooltip = "Name and keep the slots, widths, heights and window places in effect now.",
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

-- M.promptIcon asks for custom menu bar text and applies it when valid.
function M.promptIcon()
  hs.focus()
  local button, text = hs.dialog.textPrompt("Custom icon",
    "Enter 1 to " .. maxIconChars .. " characters, such as an emoji or initials.",
    hs.settings.get(keys.customIcon) or "", "Set", "Cancel")
  if button ~= "Set" then
    return
  end
  local ok, problem = M.setCustomIcon(text)
  if not ok then
    hs.alert.show(problem)
  end
end

-- iconItems builds the Icon submenu: the folders, the user's own icons, then the choices
-- that are not a single icon.
local function iconItems()
  local model = M.iconModel()
  local items = {
    {
      title = model.mark.title,
      tooltip = "Use the moorings logo in the menu bar.",
      checked = model.mark.checked,
      fn = safe(function() M.pickIcon(model.mark.name) end),
    },
  }
  for _, g in ipairs(model.groups) do
    local entries = {}
    for _, icon in ipairs(g.icons) do
      entries[#entries + 1] = {
        title = icon.glyph .. "  " .. icon.title,
        tooltip = "Show this in the menu bar.",
        checked = icon.checked,
        fn = safe(function() M.pickIcon(icon.name) end),
      }
    end
    items[#items + 1] = { title = g.title, menu = entries }
  end
  if #model.yours > 0 then
    local entries = {}
    for _, icon in ipairs(model.yours) do
      entries[#entries + 1] = {
        title = (icon.glyph and (icon.glyph .. "  ") or "") .. icon.title,
        tooltip = "Show this in the menu bar.",
        checked = icon.checked,
        fn = safe(function() M.pickIcon(icon.name) end),
      }
    end
    items[#items + 1] = { title = "Yours", menu = entries }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = {
    title = model.usingCustom and ("Custom…  " .. model.custom) or "Custom…",
    tooltip = "Type up to " .. maxIconChars .. " characters, such as an emoji or initials.",
    checked = model.usingCustom,
    fn = safe(M.promptIcon),
  }
  items[#items + 1] = {
    title = "Surprise me",
    tooltip = "Pick a different built-in icon at random.",
    fn = safe(M.surpriseIcon),
  }
  items[#items + 1] = {
    title = "Default icon",
    tooltip = "Go back to the moorings mark.",
    fn = safe(M.defaultIcon),
  }
  items[#items + 1] = {
    title = "Undo icon change",
    tooltip = "Go back to the icon you had before the last change.",
    disabled = not model.canUndo,
    fn = safe(M.undoIcon),
  }
  items[#items + 1] = { title = "-" }
  items[#items + 1] = {
    title = "Open icons folder",
    tooltip = "Drop PNG, JPEG, PDF or SVG images here to list them under Yours.",
    fn = safe(M.openIconDir),
  }
  return items
end

-- settingItems builds the Settings folder.
local function settingItems()
  local keymaps, current = {}, M.keymap()
  for _, name in ipairs(actions.keymapNames) do
    keymaps[#keymaps + 1] = {
      title = name:sub(1, 1):upper() .. name:sub(2),
      tooltip = "Use the shortcuts of this app. The Window folder shows them.",
      checked = name == current,
      fn = safe(function() M.setKeymap(name) end),
    }
  end
  local icons = iconItems()
  local front = hs.application.frontmostApplication()
  local frontBundle = front and front:bundleID()
  local ignoreTitle = "Ignore frontmost app"
  if front then
    ignoreTitle = ignoreTitle .. " (" .. (front:name() or frontBundle) .. ")"
  end
  return {
    {
      title = "Settings window…",
      tooltip = "Shortcuts, custom sizes, workspaces, icon and general settings in one window.",
      fn = safe(settings.open),
    },
    { title = "-" },
    {
      title = "Fullscreen fills the channel",
      tooltip = "A free window that goes fullscreen comes back out and fills the channel.",
      checked = fullscreenFills(),
      fn = safe(function() hs.settings.set(keys.fullscreen, not fullscreenFills()) end),
    },
    {
      title = "Fullscreen keeps anchored apps in their slots",
      tooltip = "An anchored window that goes fullscreen comes back out to its slot.",
      checked = pinFullscreenFills(),
      fn = safe(function() hs.settings.set(keys.pinFullscreen, not pinFullscreenFills()) end),
    },
    {
      title = "Snap by dragging",
      tooltip = "Drag a window to an edge or corner to snap it. "
        .. "On the ultrawide it lands in the channel.",
      checked = M.snapOn(),
      fn = safe(function() M.setSnap(not M.snapOn()) end),
    },
    {
      title = "Keep Hammerspoon up to date",
      tooltip = "Hammerspoon downloads its updates quietly and installs them when it next "
        .. "restarts.",
      checked = M.hammerspoonUpdates(),
      fn = safe(function() M.setHammerspoonUpdates(not M.hammerspoonUpdates()) end),
    },
    { title = "Keymap", menu = keymaps },
    {
      title = ignoreTitle,
      tooltip = "Turn the window shortcuts off while this app is in front.",
      checked = M.shortcutsIgnored(frontBundle),
      disabled = frontBundle == nil or ignoredBundle(frontBundle),
      fn = safe(function() M.toggleShortcutIgnore(frontBundle) end),
    },
    { title = "Icon", menu = icons },
    {
      title = "Edit config",
      tooltip = "Open anchors.lua in your text editor. Reload to apply changes.",
      fn = safe(function() hs.execute("open -t " .. shellQuote(M.path("anchors.lua"))) end),
    },
    {
      title = "Console",
      tooltip = "Open the Hammerspoon Console, where moorings logs problems.",
      fn = safe(hs.openConsole),
    },
  }
end

-- pinWindows returns the pinned windows on the ultrawide, front-most first.
local function pinWindows()
  local list = {}
  if not M.ultrawide() then
    return list
  end
  for _, w in ipairs(windows()) do
    if M.pinned(w) then
      list[#list + 1] = w
    end
  end
  return list
end

-- liftItems builds the Lift folder: one entry per pinned window, checked while lifted.
local function liftItems(pins, frozen)
  local items = {}
  for _, w in ipairs(pins) do
    items[#items + 1] = {
      title = windowApp(w),
      tooltip = "Lift this anchored window over its strip and the channel, or lower it back.",
      checked = state.lifted[w:id()] == true,
      disabled = frozen,
      fn = safe(function() M.toggleLift(w) end),
    }
  end
  if #items == 0 then
    items[1] = {
      title = "No anchored windows",
      tooltip = "Anchor an app to a slot to list its window here.",
      disabled = true,
    }
  end
  return items
end

-- menu builds the menu bar menu from current state: the two layout controls, a
-- Re-moor entry per released pin, a folder per job, and Reload. While Accessibility is
-- missing it starts with the way to grant it.
local function menu()
  local frozen = paused()
  local pins = pinWindows()
  local items = {
    {
      title = frozen and "⚓ Drop anchor (hold the layout)"
        or "⚓ Raise anchor (let windows drift)",
      tooltip = frozen
        and "Hold anchored apps in their slots and free windows in the channel again."
        or "Stop holding windows so you can arrange them freely. The shortcuts rest too.",
      fn = safe(function()
        hs.settings.set(keys.paused, not paused())
        state.placed = {}
        M.moor()
      end),
    },
    {
      title = "Re-moor now",
      tooltip = "Put every anchored window back in its slot and forget released, lifted and "
        .. "learned sizes.",
      disabled = frozen,
      fn = safe(function()
        state.bursts, state.floors, state.placed, state.released, state.lifted = {}, {}, {}, {}, {}
        M.moor()
      end),
    },
  }
  for _, w in ipairs(pins) do
    if state.released[w:id()] then
      items[#items + 1] = {
        title = "Re-moor " .. windowApp(w),
        tooltip = "You moved this window, so moorings let it go. Put it back in its slot.",
        disabled = frozen,
        fn = safe(function() M.remoor(w) end),
      }
    end
  end
  for _, it in ipairs({
    { title = "-" },
    { title = "Window", menu = windowItems() },
    { title = "Lift", menu = liftItems(pins, frozen) },
    { title = "Anchored apps", menu = lockedItems() },
    { title = "Widths", menu = widthItems() },
    { title = "Heights", menu = heightItems() },
    { title = "Workspaces", menu = workspaceItems() },
    { title = "Settings", menu = settingItems() },
    { title = "-" },
    {
      title = "Reload",
      tooltip = "Reload Hammerspoon to apply config changes, unless the config has an error.",
      fn = safe(M.reload),
    },
  }) do
    items[#items + 1] = it
  end
  if not trusted() then
    table.insert(items, 1, { title = "-" })
    table.insert(items, 1, {
      title = axGlyph .. " Grant Accessibility access",
      tooltip = "Hammerspoon needs Accessibility access before moorings can move windows.",
      fn = safe(M.openAccessibility),
    })
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
  return { {
    title = "Menu failed, see Console",
    tooltip = "Building this menu raised an error. The Console shows it.",
    fn = hs.openConsole,
  } }
end

-- start creates the menu bar item, subscribes to window events and starts polling.
function M.start()
  hs.window.animationDuration = 0
  hs.autoLaunch(true)
  hs.accessibilityState(true)
  applyHammerspoonUpdates()
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
  applyIcon()
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
    state.placed = {}
    M.moor()
  end)):start()
  M.timer = hs.timer.doEvery(M.config.pollSeconds, safe(M.moor))
  safe(M.moor)()
  return M
end

return M
