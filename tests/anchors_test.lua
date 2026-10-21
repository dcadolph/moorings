-- anchors_test drives anchors.lua against a fake Hammerspoon. Run it from the
-- repo root with: lua tests/anchors_test.lua

package.path = "./?.lua;" .. package.path

local realPrint = print
local failures, passes = 0, 0
local world, anchors

-- copy returns a plain copy of a frame.
local function copy(f)
  return { x = f.x, y = f.y, w = f.w, h = f.h }
end

-- check records a failure when cond is false.
local function check(name, cond, msg)
  if cond then
    passes = passes + 1
  else
    failures = failures + 1
    realPrint("FAIL " .. name .. ": " .. (msg or "condition false"))
  end
end

-- frameIs checks that win sits at want.
local function frameIs(name, win, want)
  local f = win.f
  check(name, f.x == want.x and f.y == want.y and f.w == want.w and f.h == want.h,
    string.format("got {%g,%g,%g,%g}, want {%g,%g,%g,%g}",
      f.x, f.y, f.w, f.h, want.x, want.y, want.w, want.h))
end

local Screen = {}
Screen.__index = Screen

-- Screen:frame returns the usable frame below the menu bar.
function Screen:frame() return copy(self.usable) end

-- Screen:fullFrame returns the whole display.
function Screen:fullFrame() return copy(self.full) end

-- Screen:id returns the display id.
function Screen:id() return self.sid end

-- newScreen builds a w by h display at x with a 25 point menu bar.
local function newScreen(id, x, w, h)
  return setmetatable({
    sid = id,
    full = { x = x, y = 0, w = w, h = h },
    usable = { x = x, y = 25, w = w, h = h - 25 },
  }, Screen)
end

local Win = {}
Win.__index = Win

-- Win:id returns the window id.
function Win:id() return self.wid end

-- Win:frame returns the current frame.
function Win:frame() return copy(self.f) end

-- Win:setFrame moves the window and counts the move.
function Win:setFrame(f)
  self.f = copy(f)
  self.moves = self.moves + 1
end

-- bundles maps the short app names used in tests to bundle IDs.
local bundles = {
  Slack = "com.tinyspeck.slackmacgap",
  iTerm2 = "com.googlecode.iterm2",
}

-- Win:application returns an app with the window's bundle ID and main window.
function Win:application()
  local name, win = self.app, self
  return {
    bundleID = function() return bundles[name] or ("test." .. name) end,
    mainWindow = function()
      for _, w in ipairs(world.windows) do
        if w.app == name and not w.secondary then return w end
      end
      return win
    end,
  }
end

-- Win:isMinimized reports a minimized window.
function Win:isMinimized() return self.minimized == true end

-- Win:isStandard reports a standard window.
function Win:isStandard() return true end

-- Win:isVisible reports a visible window.
function Win:isVisible() return true end

-- Win:isFullScreen reports native fullscreen.
function Win:isFullScreen() return self.full end

-- Win:setFullScreen enters or leaves native fullscreen.
function Win:setFullScreen(v) self.full = v end

-- Win:screen returns the screen holding the window's center.
function Win:screen()
  local cx = self.f.x + self.f.w / 2
  for _, s in ipairs(world.screens) do
    if cx >= s.full.x and cx < s.full.x + s.full.w then
      return s
    end
  end
  return world.screens[1]
end

-- addWin opens a window for app at frame, front-most.
local function addWin(app, f)
  world.nextID = world.nextID + 1
  local w = setmetatable({ wid = world.nextID, app = app, f = copy(f), moves = 0, full = false }, Win)
  table.insert(world.windows, 1, w)
  return w
end

-- focus makes win the focused window.
local function focus(win)
  world.focused = win
end

-- install builds a fresh fake Hammerspoon and loads anchors into it.
local function install(...)
  world = {
    screens = { ... }, windows = {}, settings = {}, nextID = 0, printed = {},
    clock = 1000, mouseDown = false, trusted = true,
  }
  hs = {
    configdir = "/tmp/hammerspoon",
    autoLaunch = function(v) world.autoLaunch = v end,
    accessibilityState = function(prompt)
      if prompt then world.axPrompted = true end
      return world.trusted
    end,
    mouse = { getButtons = function() return { [1] = world.mouseDown } end },
    openConsole = function() world.console = true end,
    reload = function() world.reloaded = true end,
    execute = function(cmd) world.executed = cmd end,
    settings = {
      get = function(k) return world.settings[k] end,
      set = function(k, v) world.settings[k] = v end,
    },
    screen = {
      allScreens = function() return world.screens end,
      watcher = { new = function() return { start = function(self) return self end } end },
    },
    window = {
      orderedWindows = function()
        local list = {}
        for i, w in ipairs(world.windows) do list[i] = w end
        return list
      end,
      focusedWindow = function() return world.focused end,
      get = function(id)
        for _, w in ipairs(world.windows) do
          if w.wid == id then return w end
        end
        return nil
      end,
      filter = {
        windowCreated = "windowCreated",
        windowFocused = "windowFocused",
        windowFullscreened = "windowFullscreened",
        windowUnfullscreened = "windowUnfullscreened",
        default = {
          subscribe = function(self, events, fn)
            world.events, world.onEvent = events, fn
            return self
          end,
        },
      },
    },
    menubar = {
      new = function()
        local bar = {}
        function bar:setTitle(t) self.title = t return self end
        function bar:setMenu(m) self.menu = m return self end
        world.bar = bar
        return bar
      end,
    },
    timer = {
      secondsSinceEpoch = function() return world.clock end,
      doEvery = function(s, fn)
        world.pollSeconds, world.poll = s, fn
        return {}
      end,
    },
  }
  _G.print = function(msg) world.printed[#world.printed + 1] = msg end
  package.loaded.anchors = nil
  anchors = require("anchors")
end

-- item finds a menu entry by title, searching submenus.
local function item(title, items)
  items = items or world.bar.menu()
  for _, it in ipairs(items) do
    if it.title == title then return it end
    if it.menu then
      local found = item(title, it.menu)
      if found then return found end
    end
  end
  return nil
end

-- click runs a menu entry by title.
local function click(title)
  local it = item(title)
  check("menu has " .. title, it ~= nil)
  if it then it.fn({}, it) end
end

-- ultrawide is a 5120 by 1440 display. Its usable frame is 5120 by 1415 at y 25.
local function ultrawide() return newScreen(1, 0, 5120, 1440) end

local tests = {}

-- Test 0: Edge and channel math for the default widths.
tests[#tests + 1] = function()
  install(ultrawide())
  local r = anchors.regions({ x = 0, y = 25, w = 5120, h = 1415 }, 10, 45)
  frameIs("t0 left", { f = r.left }, { x = 0, y = 25, w = 512, h = 1415 })
  frameIs("t0 channel", { f = r.channel }, { x = 512, y = 25, w = 2304, h = 1415 })
  frameIs("t0 right", { f = r.right }, { x = 2816, y = 25, w = 2304, h = 1415 })
end

-- Test 1: Start pins Slack left and iTerm right and registers the login item.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  frameIs("t1 slack", slack, { x = 0, y = 25, w = 512, h = 1415 })
  frameIs("t1 iterm", term, { x = 2816, y = 25, w = 2304, h = 1415 })
  check("t1 autolaunch", world.autoLaunch == true)
  check("t1 ax prompt", world.axPrompted == true)
  check("t1 title", world.bar.title == "⛵")
  check("t1 poll", world.pollSeconds == 0.25 and world.poll ~= nil)
  check("t1 events", world.events and #world.events == 4)
end

-- Test 2: A free window is pushed into the channel and shrunk to fit.
tests[#tests + 1] = function()
  install(ultrawide())
  local small = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  local wide = addWin("Chrome", { x = 300, y = 25, w = 4000, h = 1415 })
  anchors.start()
  frameIs("t2 small", small, { x = 512, y = 25, w = 800, h = 600 })
  frameIs("t2 wide", wide, { x = 512, y = 25, w = 2304, h = 1415 })
end

-- Test 3: A free window already in the channel is never touched.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  world.poll()
  check("t3 untouched", w.moves == 0, "moves " .. w.moves)
end

-- Test 4: Focusing Slack expands it to 30 percent and focusing another app collapses it.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", { x = 0, y = 25, w = 512, h = 1415 })
  local other = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  focus(slack)
  world.onEvent()
  frameIs("t4 expanded", slack, { x = 0, y = 25, w = 1536, h = 1415 })
  check("t4 channel kept", other.moves == 0)
  focus(other)
  world.onEvent()
  frameIs("t4 collapsed", slack, { x = 0, y = 25, w = 512, h = 1415 })
end

-- Test 5: A screen narrower than the aspect cutoff is left alone.
tests[#tests + 1] = function()
  install(newScreen(1, 0, 1920, 1080))
  local slack = addWin("Slack", { x = 500, y = 100, w = 900, h = 700 })
  anchors.start()
  check("t5 untouched", slack.moves == 0)
end

-- Test 6: Pins on a second screen move to the ultrawide, free windows there stay.
tests[#tests + 1] = function()
  install(newScreen(1, 0, 1920, 1080), newScreen(2, 1920, 5120, 1440))
  local slack = addWin("Slack", { x = 100, y = 100, w = 900, h = 700 })
  local free = addWin("Safari", { x = 0, y = 25, w = 1920, h = 1055 })
  anchors.start()
  frameIs("t6 slack", slack, { x = 1920, y = 25, w = 512, h = 1415 })
  check("t6 free stays", free.moves == 0)
end

-- Test 7: Drop anchor freezes the layout, survives reload, and Weigh anchor resumes.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  click("⚓ Drop anchor (freeze layout)")
  local w = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  world.poll()
  check("t7 frozen", w.moves == 0)
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  anchors.start()
  check("t7 survives reload", item("⚓ Weigh anchor (resume layout)") ~= nil)
  local w2 = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  world.poll()
  check("t7 still frozen", w2.moves == 0)
  click("⚓ Weigh anchor (resume layout)")
  frameIs("t7 resumed", w2, { x = 512, y = 25, w = 800, h = 600 })
end

-- Test 8: Every preset sets both edges and the channel, and wins over the file widths.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", { x = 0, y = 25, w = 512, h = 1415 })
  local term = addWin("iTerm2", { x = 2816, y = 25, w = 2304, h = 1415 })
  anchors.start()
  for _, p in ipairs(anchors.presets) do
    local title = string.format("Left %d%%, right %d%%", p.left, p.right)
    click(title)
    local lw = math.floor(5120 * p.left / 100)
    local rw = math.floor(5120 * p.right / 100)
    frameIs("t8 slack " .. title, slack, { x = 0, y = 25, w = lw, h = 1415 })
    frameIs("t8 iterm " .. title, term, { x = 5120 - rw, y = 25, w = rw, h = 1415 })
    local ch = anchors.channel(world.screens[1])
    check("t8 channel " .. title, ch.x == lw and ch.w == 5120 - lw - rw,
      string.format("got x %d w %d", ch.x, ch.w))
    check("t8 checked " .. title, item(title).checked == true)
  end
  anchors.config.leftPct = 30
  check("t8 preset wins", select(1, anchors.widths()) == 20)
end

-- Test 9: A window the channel narrowed grows back when a preset widens the channel.
tests[#tests + 1] = function()
  install(ultrawide())
  local wide = addWin("Chrome", { x = 600, y = 25, w = 2200, h = 1415 })
  anchors.start()
  click("Left 20%, right 40%")
  check("t9 narrowed", wide.f.w == 2048, "w " .. wide.f.w)
  click("Left 10%, right 30%")
  check("t9 grew back", wide.f.w == 2200, "w " .. wide.f.w)
end

-- Test 10: A window the user resized after a clamp keeps the user's width.
tests[#tests + 1] = function()
  install(ultrawide())
  local wide = addWin("Chrome", { x = 600, y = 25, w = 2200, h = 1415 })
  anchors.start()
  click("Left 20%, right 40%")
  wide.f.w = 1200
  click("Left 10%, right 30%")
  check("t10 user width kept", wide.f.w == 1200, "w " .. wide.f.w)
end

-- Test 11: Fill channel stretches the focused window and Undo tidy restores it.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  check("t11 undo disabled", item("Undo tidy").disabled == true)
  focus(w)
  click("Fill channel")
  frameIs("t11 filled", w, { x = 512, y = 25, w = 2304, h = 1415 })
  check("t11 undo enabled", item("Undo tidy").disabled == false)
  click("Undo tidy")
  frameIs("t11 restored", w, { x = 1000, y = 200, w = 800, h = 600 })
end

-- Test 12: Fill channel ignores a focused pin.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", { x = 0, y = 25, w = 512, h = 1415 })
  anchors.start()
  focus(slack)
  click("Fill channel")
  check("t12 no save", not anchors.canUndo())
end

-- Test 13: Tidy into 2 and 3 columns uses the front-most free windows in left-to-right order.
tests[#tests + 1] = function()
  install(ultrawide())
  local back = addWin("Notes", { x = 2000, y = 100, w = 400, h = 400 })
  local a = addWin("Safari", { x = 1500, y = 100, w = 400, h = 400 })
  local b = addWin("Chrome", { x = 700, y = 100, w = 400, h = 400 })
  addWin("Slack", { x = 0, y = 25, w = 512, h = 1415 })
  anchors.start()
  click("Halves")
  frameIs("t13 b left", b, { x = 512, y = 25, w = 1152, h = 1415 })
  frameIs("t13 a right", a, { x = 1664, y = 25, w = 1152, h = 1415 })
  check("t13 back untouched", back.moves == 0)
  click("Thirds")
  frameIs("t13 back col", back, { x = 2048, y = 25, w = 768, h = 1415 })
  click("Undo tidy")
  frameIs("t13 a restored", a, { x = 1500, y = 100, w = 400, h = 400 })
  frameIs("t13 b restored", b, { x = 700, y = 100, w = 400, h = 400 })
  frameIs("t13 back restored", back, { x = 2000, y = 100, w = 400, h = 400 })
  check("t13 undo cleared", not anchors.canUndo())
end

-- Test 14: Native fullscreen on the ultrawide is turned into a channel fill.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  w.full = true
  world.onEvent()
  check("t14 left fullscreen", w.full == false)
  world.poll()
  frameIs("t14 filled", w, { x = 512, y = 25, w = 2304, h = 1415 })
end

-- Test 15: Unticking Fullscreen fills the channel leaves native fullscreen alone.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  click("Fullscreen fills the channel")
  check("t15 unchecked", item("Fullscreen fills the channel").checked == false)
  w.full = true
  world.poll()
  check("t15 still fullscreen", w.full == true)
end

-- Test 16: The chosen icon sets the title and survives reload.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  click("🐙  Octopus")
  check("t16 title", world.bar.title == "🐙")
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  anchors.start()
  check("t16 survives reload", world.bar.title == "🐙")
  check("t16 checked", item("🐙  Octopus").checked == true)
end

-- Test 17: Edit config, Console and Reload call into Hammerspoon.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  click("Edit config")
  check("t17 edit", world.executed == "open -t /tmp/hammerspoon/anchors.lua")
  click("Console")
  check("t17 console", world.console == true)
  click("Reload")
  check("t17 reload", world.reloaded == true)
end

-- Test 18: An error inside a callback is logged instead of raised.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  hs.screen.allScreens = function() error("boom") end
  local ok = pcall(world.poll)
  check("t18 no raise", ok)
  check("t18 logged", world.printed[1] and world.printed[1]:find("boom") ~= nil)
end

-- Test 19: A broken menu build falls back to a Console entry.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  hs.settings.get = function() error("bad settings") end
  local items = world.bar.menu()
  check("t19 fallback", items[1].title == "Menu failed, see Console")
end

-- Test 20: Nothing moves while the mouse button is held.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  world.mouseDown = true
  anchors.start()
  check("t20 held", w.moves == 0)
  world.mouseDown = false
  world.poll()
  frameIs("t20 released", w, { x = 512, y = 25, w = 800, h = 600 })
end

-- Test 21: Without Accessibility nothing moves and the warning prints once.
tests[#tests + 1] = function()
  install(ultrawide())
  world.trusted = false
  local w = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  anchors.start()
  world.poll()
  check("t21 untouched", w.moves == 0)
  local warnings = 0
  for _, m in ipairs(world.printed) do
    if m:find("Accessibility") then warnings = warnings + 1 end
  end
  check("t21 warned once", warnings == 1, "warnings " .. warnings)
end

-- Test 22: mainOnly leaves Slack's other windows where they are.
tests[#tests + 1] = function()
  install(ultrawide())
  local main = addWin("Slack", { x = 1000, y = 100, w = 900, h = 700 })
  local huddle = addWin("Slack", { x = 1200, y = 200, w = 400, h = 300 })
  huddle.secondary = true
  anchors.start()
  frameIs("t22 main", main, { x = 0, y = 25, w = 512, h = 1415 })
  check("t22 huddle stays", huddle.moves == 0)
end

-- Test 23: An ignored bundle is never moved.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.ignoreBundles = { "test.Zoom" }
  local w = addWin("Zoom", { x = 0, y = 25, w = 800, h = 600 })
  anchors.start()
  check("t23 ignored", w.moves == 0)
end

-- Test 24: Minimized windows are skipped.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  w.minimized = true
  anchors.start()
  check("t24 minimized", w.moves == 0)
end

-- Test 25: A window that keeps moving back is held off for 60 seconds.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  anchors.start()
  for _ = 1, 3 do
    w.f.x = 0
    world.clock = world.clock + 1
    world.poll()
  end
  check("t25 four moves", w.moves == 4, "moves " .. w.moves)
  w.f.x = 0
  world.clock = world.clock + 1
  world.poll()
  check("t25 held", w.moves == 4 and w.f.x == 0, "moves " .. w.moves)
  world.clock = world.clock + 61
  world.poll()
  check("t25 resumed", w.f.x == 512)
end

-- Test 26: Widths that leave no channel fall back to the defaults.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.leftPct, anchors.config.rightPct = 50, 45
  local l, r = anchors.widths()
  check("t26 fallback", l == 10 and r == 45)
end

-- Test 27: The widest qualifying screen wins.
tests[#tests + 1] = function()
  install(newScreen(1, 0, 3440, 1440), newScreen(2, 3440, 5120, 1440))
  check("t27 widest", anchors.ultrawide():id() == 2)
end

-- Test 28: A fullscreen exit that never lands within 5 seconds is not filled later.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  w.full = true
  world.poll()
  world.clock = world.clock + 10
  world.poll()
  frameIs("t28 not filled", w, { x = 1000, y = 200, w = 800, h = 600 })
end

-- Test 29: Freezing grays out the actions and makes them no-ops.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  click("⚓ Drop anchor (freeze layout)")
  for _, t in ipairs({ "Re-moor now", "Fill channel", "Tidy channel", "Undo tidy" }) do
    check("t29 disabled " .. t, item(t).disabled == true)
  end
  focus(w)
  anchors.fill()
  check("t29 fill no-op", w.moves == 0)
end

for i, t in ipairs(tests) do
  local ok, err = pcall(t)
  if not ok then
    failures = failures + 1
    realPrint(string.format("FAIL test %d raised: %s", i - 1, err))
  end
end
_G.print = realPrint
print(string.format("%d checks passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
