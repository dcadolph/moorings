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

-- bundleFor returns the bundle ID of a test app name.
local function bundleFor(name)
  return bundles[name] or ("test." .. name)
end

-- nameFor returns the test app name of a bundle ID, or nil.
local function nameFor(bundle)
  for name, id in pairs(bundles) do
    if id == bundle then return name end
  end
  return bundle:match("^test%.(.+)$")
end

-- newApp builds a running app with a name and a Dock kind.
local function newApp(name, kind)
  return {
    bundleID = function() return bundleFor(name) end,
    name = function() return name end,
    kind = function() return kind or 1 end,
  }
end

-- Win:application returns an app with the window's bundle ID and main window.
function Win:application()
  local name, win = self.app, self
  return {
    bundleID = function() return bundleFor(name) end,
    mainWindow = function()
      for _, w in ipairs(world.windows) do
        if w.app == name and not w.secondary then return w end
      end
      return win
    end,
  }
end

-- Win:title returns the window title, the app name unless a test sets one.
function Win:title() return self.name or self.app end

-- Win:focus makes the window the focused one.
function Win:focus() world.focused = self end

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
    screens = { ... }, windows = {}, settings = {}, nextID = 0, printed = {}, apps = {},
    clock = 1000, mouseDown = false, trusted = true, hotkeys = {}, taps = {}, urls = {},
  }
  hs = {
    hotkey = {
      new = function(mods, key, fn)
        if key == "bogus" then error("unknown key") end
        local hk = { mods = table.concat(mods, "+"), key = key, fn = fn, enabled = false }
        function hk:enable() self.enabled = true return self end
        function hk:disable() self.enabled = false return self end
        function hk:delete() self.deleted, self.enabled = true, false end
        world.hotkeys[#world.hotkeys + 1] = hk
        return hk
      end,
    },
    configdir = "/tmp/hammerspoon",
    autoLaunch = function(v) world.autoLaunch = v end,
    accessibilityState = function(prompt)
      if prompt then world.axPrompted = true end
      return world.trusted
    end,
    mouse = {
      getButtons = function() return { [1] = world.mouseDown } end,
      absolutePosition = function() return world.mousePos end,
    },
    eventtap = {
      event = {
        types = {
          leftMouseDown = 1, leftMouseUp = 2, leftMouseDragged = 6, otherMouseDown = 25,
          otherMouseUp = 26,
        },
        properties = { mouseEventButtonNumber = 3 },
      },
      new = function(types, fn)
        local tap = { types = types, fn = fn }
        function tap:start() self.running = true return self end
        function tap:stop() self.running = false return self end
        world.taps[#world.taps + 1] = tap
        if types[1] == 1 then
          world.tapTypes, world.tap = types, fn
          world.tapping = true
        end
        return tap
      end,
    },
    urlevent = { bind = function(name, fn) world.urls[name] = fn end },
    focus = function() world.hsFocused = true end,
    dialog = {
      textPrompt = function(...)
        world.promptArgs = { ... }
        return table.unpack(world.prompt or { "Cancel", "" })
      end,
    },
    canvas = {
      new = function(frame)
        local c = { f = copy(frame), shown = false }
        function c:appendElements(e) self.element = e return self end
        function c:level(l) self.lvl = l return self end
        function c:show() self.shown = true return self end
        function c:frame(f) self.f = copy(f) return self end
        function c:delete() self.deleted = true world.canvas = nil end
        world.canvas, world.canvases = c, (world.canvases or 0) + 1
        return c
      end,
    },
    openConsole = function() world.console = true end,
    reload = function() world.reloaded = true end,
    execute = function(cmd) world.executed = cmd end,
    alert = { show = function(msg) world.alerted = msg end },
    settings = {
      get = function(k) return world.settings[k] end,
      set = function(k, v) world.settings[k] = v end,
      clear = function(k) world.settings[k] = nil end,
    },
    application = {
      runningApplications = function()
        local list, seen = {}, {}
        for _, w in ipairs(world.windows) do
          if not seen[w.app] then
            seen[w.app] = true
            list[#list + 1] = newApp(w.app)
          end
        end
        for _, app in ipairs(world.apps) do list[#list + 1] = app end
        return list
      end,
      frontmostApplication = function()
        if world.front then return newApp(world.front) end
        return world.focused and newApp(world.focused.app) or nil
      end,
      nameForBundleID = function(bundle) return nameFor(bundle) end,
      watcher = {
        activated = 5,
        new = function(fn)
          world.appWatch = fn
          return { start = function(self) return self end }
        end,
      },
    },
    screen = {
      allScreens = function() return world.screens end,
      watcher = {
        new = function(fn)
          world.onScreens = fn
          return { start = function(self) return self end }
        end,
      },
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
      doAfter = function(_, fn)
        fn()
        return {}
      end,
    },
  }
  _G.print = function(msg) world.printed[#world.printed + 1] = msg end
  package.loaded.anchors = nil
  package.loaded.geometry = nil
  package.loaded.actions = nil
  package.loaded.snap = nil
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
  local tidy = item("Tidy channel").menu
  item("Halves", tidy).fn()
  frameIs("t13 b left", b, { x = 512, y = 25, w = 1152, h = 1415 })
  frameIs("t13 a right", a, { x = 1664, y = 25, w = 1152, h = 1415 })
  check("t13 back untouched", back.moves == 0)
  item("Thirds", tidy).fn()
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
  check("t17 edit", world.executed == "open -t '/tmp/hammerspoon/moorings/anchors.lua'")
  click("Console")
  check("t17 console", world.console == true)
  anchors.loadfile = function() return function() end end
  click("Reload")
  check("t17 reload", world.reloaded == true)
end

-- Test 30: Reload is refused with an alert when the config does not compile.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  anchors.loadfile = function() return nil, "anchors.lua:9: unexpected symbol" end
  click("Reload")
  check("t30 not reloaded", world.reloaded == nil)
  check("t30 alerted", world.alerted ~= nil)
  check("t30 logged", world.printed[#world.printed] ~= nil
    and world.printed[#world.printed]:find("unexpected symbol", 1, true) ~= nil)
end

-- Test 31: Edit config quotes a config directory that holds spaces and quotes.
tests[#tests + 1] = function()
  install(ultrawide())
  hs.configdir = "/tmp/my dir/it's"
  anchors.start()
  click("Edit config")
  check("t31 quoted", world.executed == "open -t '/tmp/my dir/it'\\''s/moorings/anchors.lua'",
    tostring(world.executed))
end

-- Test 32: A bundle pinned twice is reported and the first entry wins.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins[#anchors.config.pins + 1] =
    { bundle = "com.tinyspeck.slackmacgap", side = "right" }
  anchors.start()
  local said = false
  for _, line in ipairs(world.printed) do
    if line:find("pinned twice", 1, true) then said = true end
  end
  check("t32 reported", said)
  local win = addWin("Slack", { x = 3000, y = 100, w = 300, h = 300 })
  anchors.moor()
  frameIs("t32 first wins", win, { x = 0, y = 25, w = 512, h = 1415 })
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

-- said counts the printed lines that contain text.
local function said(text)
  local n = 0
  for _, line in ipairs(world.printed) do
    if line:find(text, 1, true) then n = n + 1 end
  end
  return n
end

-- Left, right and the halves of the default ultrawide strips.
local leftFull = { x = 0, y = 25, w = 512, h = 1415 }
local leftTop = { x = 0, y = 25, w = 512, h = 707 }
local leftBottom = { x = 0, y = 732, w = 512, h = 708 }
local rightFull = { x = 2816, y = 25, w = 2304, h = 1415 }

-- Test 33: Slot frames split a strip into halves that tile it exactly.
tests[#tests + 1] = function()
  install(ultrawide())
  local f = { x = 0, y = 25, w = 5120, h = 1415 }
  frameIs("t33 full", { f = anchors.slot(f, "left", nil, 10) }, leftFull)
  frameIs("t33 left top", { f = anchors.slot(f, "left", "top", 10) }, leftTop)
  frameIs("t33 left bottom", { f = anchors.slot(f, "left", "bottom", 10) }, leftBottom)
  frameIs("t33 right top", { f = anchors.slot(f, "right", "top", 45) },
    { x = 2816, y = 25, w = 2304, h = 707 })
  frameIs("t33 right bottom", { f = anchors.slot(f, "right", "bottom", 45) },
    { x = 2816, y = 732, w = 2304, h = 708 })
end

-- Test 34: Two pins on a side stack in config order and a lone pin keeps full height.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left" },
    { bundle = "test.Notes", side = "left" },
    { bundle = "com.googlecode.iterm2", side = "right" },
  }
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  frameIs("t34 slack top", slack, leftTop)
  frameIs("t34 notes bottom", notes, leftBottom)
  frameIs("t34 iterm full", term, rightFull)
end

-- Test 35: Explicit rows win over config order.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left", row = "bottom" },
    { bundle = "test.Notes", side = "left", row = "top" },
  }
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  anchors.start()
  frameIs("t35 slack bottom", slack, leftBottom)
  frameIs("t35 notes top", notes, leftTop)
end

-- Test 36: A side whose only pin asks for the bottom row fills the full height.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = { { bundle = "test.Notes", side = "left", row = "bottom" } }
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  anchors.start()
  frameIs("t36 notes full", notes, leftFull)
end

-- Test 37: A pinned app that is not running leaves its half empty.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left" },
    { bundle = "test.Notes", side = "left" },
  }
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  anchors.start()
  world.poll()
  frameIs("t37 notes keeps bottom", notes, leftBottom)
end

-- Test 38: A third pin on a side is reported once and its windows stay free.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left" },
    { bundle = "test.Notes", side = "left" },
    { bundle = "test.Mail", side = "left", row = "top" },
  }
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  local mail = addWin("Mail", { x = 0, y = 25, w = 800, h = 600 })
  anchors.start()
  for _ = 1, 3 do
    world.clock = world.clock + 100
    world.poll()
    world.bar.menu()
  end
  check("t38 reported once", said("test.Mail is a third pin on the left") == 1,
    "count " .. said("test.Mail is a third pin on the left"))
  frameIs("t38 slack top", slack, leftTop)
  frameIs("t38 notes bottom", notes, leftBottom)
  frameIs("t38 mail free", mail, { x = 512, y = 25, w = 800, h = 600 })
end

-- Test 39: Two pins asking for the same row are reported and the second takes the other.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left", row = "top" },
    { bundle = "test.Notes", side = "left", row = "top" },
  }
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  anchors.start()
  check("t39 reported", said("both ask for the top row on the left") == 1)
  frameIs("t39 slack top", slack, leftTop)
  frameIs("t39 notes bottom", notes, leftBottom)
end

-- Test 40: An unknown row is reported and treated as unset.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "test.Notes", side = "left", row = "middle" },
    { bundle = "com.tinyspeck.slackmacgap", side = "left", row = "top" },
  }
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  anchors.start()
  check("t40 reported", said("test.Notes has row middle") == 1)
  frameIs("t40 slack top", slack, leftTop)
  frameIs("t40 notes bottom", notes, leftBottom)
end

-- Test 41: A pin without a valid side is reported and its windows stay free.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = { { bundle = "test.Notes", side = "middle" } }
  local notes = addWin("Notes", { x = 0, y = 25, w = 400, h = 400 })
  anchors.start()
  check("t41 reported", said("a pin needs a bundle and a side") == 1)
  frameIs("t41 notes free", notes, { x = 512, y = 25, w = 400, h = 400 })
end

-- Test 42: Expand on focus widens a stacked pin inside its own half only.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left", row = "top", expandPct = 30 },
    { bundle = "test.Notes", side = "left", row = "bottom", expandPct = 20 },
  }
  local slack = addWin("Slack", leftTop)
  local notes = addWin("Notes", leftBottom)
  anchors.start()
  focus(slack)
  world.onEvent()
  frameIs("t42 slack expanded", slack, { x = 0, y = 25, w = 1536, h = 707 })
  frameIs("t42 notes kept", notes, leftBottom)
  focus(notes)
  world.onEvent()
  frameIs("t42 slack collapsed", slack, leftTop)
  frameIs("t42 notes expanded", notes, { x = 0, y = 732, w = 1024, h = 708 })
end

-- Test 43: A stacked pin on the right expands leftward inside its half.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.googlecode.iterm2", side = "right", row = "bottom", expandPct = 60 },
    { bundle = "test.Notes", side = "right" },
  }
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  anchors.start()
  frameIs("t43 notes top", notes, { x = 2816, y = 25, w = 2304, h = 707 })
  frameIs("t43 iterm bottom", term, { x = 2816, y = 732, w = 2304, h = 708 })
  focus(term)
  world.onEvent()
  frameIs("t43 iterm expanded", term, { x = 2048, y = 732, w = 3072, h = 708 })
end

-- Test 44: Every window of a stacked app goes to its half, and mainOnly moves only the main one.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left", mainOnly = true },
    { bundle = "test.Notes", side = "left" },
  }
  local main = addWin("Slack", { x = 1000, y = 100, w = 900, h = 700 })
  local huddle = addWin("Slack", { x = 1200, y = 200, w = 400, h = 300 })
  huddle.secondary = true
  local n1 = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  local n2 = addWin("Notes", { x = 3000, y = 300, w = 600, h = 500 })
  n2.secondary = true
  anchors.start()
  frameIs("t44 slack main top", main, leftTop)
  check("t44 huddle stays", huddle.moves == 0)
  frameIs("t44 notes first bottom", n1, leftBottom)
  frameIs("t44 notes second bottom", n2, leftBottom)
end

-- Test 45: A preset resizes both halves of a stacked strip.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left" },
    { bundle = "test.Notes", side = "left" },
  }
  local slack = addWin("Slack", leftTop)
  local notes = addWin("Notes", leftBottom)
  anchors.start()
  click("Left 20%, right 40%")
  frameIs("t45 slack top", slack, { x = 0, y = 25, w = 1024, h = 707 })
  frameIs("t45 notes bottom", notes, { x = 0, y = 732, w = 1024, h = 708 })
end

-- pick runs choice in the submenu of the row titled row.
local function pick(row, choice)
  local it = item(row)
  check("menu has " .. row, it ~= nil and it.menu ~= nil)
  if not (it and it.menu) then return end
  local c = item(choice, it.menu)
  check("row " .. row .. " has " .. choice, c ~= nil)
  if c then c.fn({}, c) end
end

-- titles lists the titles of a submenu.
local function titles(items)
  local out = {}
  for i, it in ipairs(items) do out[i] = it.title end
  return table.concat(out, ",")
end

-- folder returns the submenu of the top-level folder titled title.
local function folder(title)
  for _, it in ipairs(world.bar.menu()) do
    if it.title == title then return it.menu end
  end
  return {}
end

-- rows lists the four slot row titles.
local function rows()
  local out = {}
  for _, it in ipairs(folder("Locked apps")) do
    if it.title:find("^Left ") or it.title:find("^Right ") then
      if it.menu then out[#out + 1] = it.title end
    end
  end
  return table.concat(out, ",")
end

-- defaultRows is the row titles for the default config.
local defaultRows = "Left top: Slack,Left bottom: Empty,Right top: iTerm2,Right bottom: Empty"

local rightTop = { x = 2816, y = 25, w = 2304, h = 707 }
local rightBottom = { x = 2816, y = 732, w = 2304, h = 708 }

-- Test 46: The slot rows show the config layout and offer Empty plus running apps.
tests[#tests + 1] = function()
  install(ultrawide())
  addWin("Slack", leftFull)
  addWin("iTerm2", rightFull)
  addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  check("t46 rows", rows() == defaultRows, rows())
  local choices = item("Left top: Slack").menu
  check("t46 choices", titles(choices) == "Empty,iTerm2,Safari,Slack", titles(choices))
  check("t46 checked", item("Slack", choices).checked == true)
  check("t46 empty unchecked", item("Empty", choices).checked == false)
  check("t46 reset disabled", item("Reset to defaults").disabled == true)
end

-- Test 47: Picking an app for an empty slot stacks it, and the choice survives reload.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local notes = addWin("Notes", { x = 1000, y = 200, w = 400, h = 400 })
  anchors.start()
  pick("Left bottom: Empty", "Notes")
  frameIs("t47 slack top", slack, leftTop)
  frameIs("t47 notes bottom", notes, leftBottom)
  check("t47 row", item("Left bottom: Notes") ~= nil)
  check("t47 reset enabled", item("Reset to defaults").disabled == false)
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  local slack2 = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  local notes2 = addWin("Notes", { x = 1000, y = 200, w = 400, h = 400 })
  anchors.start()
  frameIs("t47 reload slack top", slack2, leftTop)
  frameIs("t47 reload notes bottom", notes2, leftBottom)
end

-- Test 48: Picking an app that sits in another slot moves it, so it holds one slot.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local term = addWin("iTerm2", rightFull)
  anchors.start()
  pick("Right bottom: Empty", "Slack")
  check("t48 rows",
    rows() == "Left top: Empty,Left bottom: Empty,Right top: iTerm2,Right bottom: Slack", rows())
  frameIs("t48 slack right bottom", slack, rightBottom)
  frameIs("t48 iterm right top", term, rightTop)
end

-- Test 49: A chosen app keeps its config expandPct and mainOnly, and others get neither.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local huddle = addWin("Slack", { x = 1200, y = 200, w = 400, h = 300 })
  huddle.secondary = true
  local n1 = addWin("Notes", { x = 1000, y = 200, w = 400, h = 400 })
  local n2 = addWin("Notes", { x = 1500, y = 300, w = 500, h = 400 })
  n2.secondary = true
  anchors.start()
  pick("Left bottom: Empty", "Notes")
  check("t49 huddle stays", huddle.moves == 0)
  focus(slack)
  world.onEvent()
  frameIs("t49 slack expanded", slack, { x = 0, y = 25, w = 1536, h = 707 })
  focus(n1)
  world.onEvent()
  frameIs("t49 notes not expanded", n1, leftBottom)
  frameIs("t49 notes second window", n2, leftBottom)
end

-- Test 50: Empty clears a slot and its app's window goes back to the channel.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  pick("Left top: Slack", "Empty")
  check("t50 row", item("Left top: Empty") ~= nil)
  frameIs("t50 slack free", slack, { x = 512, y = 25, w = 512, h = 1415 })
end

-- Test 51: Pin frontmost app puts the app last used in the chosen slot.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", rightFull)
  local safari = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  world.front = "Safari"
  anchors.start()
  local fast = item("Pin frontmost app (Safari)")
  check("t51 enabled", fast ~= nil and fast.disabled == false)
  pick("Pin frontmost app (Safari)", "Right bottom")
  frameIs("t51 safari right bottom", safari, rightBottom)
  frameIs("t51 iterm right top", term, rightTop)
  local target = item("Right bottom", item("Pin frontmost app (Safari)").menu)
  check("t51 checked", target.checked == true)
end

-- Test 52: Pin frontmost app is disabled for an ignored app.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.ignoreBundles = { "test.Zoom" }
  world.front = "Zoom"
  anchors.start()
  check("t52 disabled", item("Pin frontmost app (Zoom)").disabled == true)
end

-- Test 53: Reset to defaults restores the config layout and clears the saved choice.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local term = addWin("iTerm2", rightFull)
  anchors.start()
  pick("Right bottom: Empty", "Slack")
  click("Reset to defaults")
  check("t53 cleared", world.settings["moorings.slots"] == nil)
  frameIs("t53 slack left", slack, leftFull)
  frameIs("t53 iterm right", term, rightFull)
  check("t53 rows", rows() == defaultRows, rows())
end

-- Test 54: The app list leaves out ignored apps, apps without a Dock icon, and repeats.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.ignoreBundles = { "test.Zoom" }
  world.apps = { newApp("Helper", 0), newApp("Zoom"), newApp("Safari"), newApp("Safari") }
  anchors.start()
  local choices = item("Left bottom: Empty").menu
  check("t54 choices", titles(choices) == "Empty,Safari", titles(choices))
end

-- Test 55: A corrupt saved choice falls back to the config, and a bad slot value is empty.
tests[#tests + 1] = function()
  install(ultrawide())
  world.settings["moorings.slots"] = "junk"
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  anchors.start()
  frameIs("t55 config layout", slack, leftFull)
  install(ultrawide())
  world.settings["moorings.slots"] = { ["left-top"] = 42, ["right-top"] = "test.Notes" }
  local slack2 = addWin("Slack", leftFull)
  local notes = addWin("Notes", { x = 1000, y = 200, w = 400, h = 400 })
  anchors.start()
  frameIs("t55 slack free", slack2, { x = 512, y = 25, w = 512, h = 1415 })
  frameIs("t55 notes right", notes, rightFull)
  check("t55 rows",
    rows() == "Left top: Empty,Left bottom: Empty,Right top: Notes,Right bottom: Empty", rows())
end

-- Test 56: A chosen app that quits keeps its slot name and leaves its half empty.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  addWin("Notes", { x = 1000, y = 200, w = 400, h = 400 })
  anchors.start()
  pick("Left bottom: Empty", "Notes")
  table.remove(world.windows, 1)
  world.poll()
  check("t56 row", item("Left bottom: Notes") ~= nil)
  frameIs("t56 slack keeps top", slack, leftTop)
end

-- checkedPresets lists the titles of the checked presets.
local function checkedPresets()
  local out = {}
  for _, it in ipairs(folder("Widths")) do
    if it.title:find("^Left %d+%%, right") and it.checked then out[#out + 1] = it.title end
  end
  return table.concat(out, ",")
end

-- Test 57: The channel label shows what the strips leave over.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  check("t57 default", item("Channel 45%") ~= nil and item("Channel 45%").disabled == true)
  click("Left 20%, right 40%")
  check("t57 preset", item("Channel 40%") ~= nil)
end

-- Test 58: Each stepper moves only its own side by one point, and the label follows.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local term = addWin("iTerm2", rightFull)
  anchors.start()
  click("Left wider")
  frameIs("t58 left wider", slack, { x = 0, y = 25, w = 563, h = 1415 })
  frameIs("t58 right kept", term, rightFull)
  check("t58 label", item("Channel 44%") ~= nil)
  check("t58 no preset", checkedPresets() == "", checkedPresets())
  click("Left narrower")
  click("Left narrower")
  frameIs("t58 left narrower", slack, { x = 0, y = 25, w = 460, h = 1415 })
  click("Right narrower")
  frameIs("t58 right narrower", term, { x = 2868, y = 25, w = 2252, h = 1415 })
  frameIs("t58 left kept", slack, { x = 0, y = 25, w = 460, h = 1415 })
  click("Right wider")
  frameIs("t58 right wider", term, rightFull)
  check("t58 label after", item("Channel 46%") ~= nil)
end

-- Test 59: Stepping back onto a preset's widths checks that preset.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  click("Left wider")
  click("Left narrower")
  check("t59 preset checked", checkedPresets() == "Left 10%, right 45%", checkedPresets())
end

-- Test 60: A step that would leave the channel under 10 percent is disabled and refused.
tests[#tests + 1] = function()
  install(ultrawide())
  world.settings["moorings.widths"] = { left = 45, right = 45 }
  local slack = addWin("Slack", leftFull)
  anchors.start()
  check("t60 label", item("Channel 10%") ~= nil)
  check("t60 left wider off", item("Left wider").disabled == true)
  check("t60 right wider off", item("Right wider").disabled == true)
  check("t60 narrower on", item("Left narrower").disabled == false)
  check("t60 refused", anchors.step("left", 1) == false)
  local l, r = anchors.widths()
  check("t60 unchanged", l == 45 and r == 45)
  frameIs("t60 slack", slack, { x = 0, y = 25, w = 2304, h = 1415 })
end

-- Test 61: A strip cannot be narrowed to zero.
tests[#tests + 1] = function()
  install(ultrawide())
  world.settings["moorings.widths"] = { left = 1, right = 45 }
  anchors.start()
  check("t61 left narrower off", item("Left narrower").disabled == true)
  check("t61 refused", anchors.step("left", -1) == false)
  check("t61 unchanged", select(1, anchors.widths()) == 1)
end

-- Test 62: A stepped width survives reload.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  click("Right narrower")
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  local term = addWin("iTerm2", rightFull)
  anchors.start()
  frameIs("t62 right kept", term, { x = 2868, y = 25, w = 2252, h = 1415 })
  check("t62 label", item("Channel 46%") ~= nil)
end

-- Test 63: A saved width that leaves no channel falls back to the config.
tests[#tests + 1] = function()
  install(ultrawide())
  world.settings["moorings.widths"] = { left = 60, right = 45 }
  local l, r = anchors.widths()
  check("t63 fallback", l == 10 and r == 45)
  world.settings["moorings.widths"] = "junk"
  l, r = anchors.widths()
  check("t63 junk", l == 10 and r == 45)
end

-- Test 64: The action area is the channel on the ultrawide and the usable frame elsewhere.
tests[#tests + 1] = function()
  local laptop = newScreen(2, 5120, 1512, 982)
  install(ultrawide(), laptop)
  local a = anchors.area(world.screens[1])
  check("t64 channel", a.x == 512 and a.y == 25 and a.w == 2304 and a.h == 1415,
    string.format("{%g,%g,%g,%g}", a.x, a.y, a.w, a.h))
  a = anchors.area(laptop)
  check("t64 laptop", a.x == 5120 and a.y == 25 and a.w == 1512 and a.h == 957)
end

-- Test 65: Reload checks every moorings file and refuses when any one fails.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  local seen = {}
  anchors.loadfile = function(path)
    seen[#seen + 1] = path
    if path:find("geometry.lua", 1, true) then return nil, "geometry.lua:3: oops" end
    return function() end
  end
  click("Reload")
  check("t65 not reloaded", world.reloaded == nil)
  check("t65 checked both", seen[1] == "/tmp/hammerspoon/moorings/anchors.lua"
    and seen[2] == "/tmp/hammerspoon/moorings/geometry.lua")
end

-- hotkey returns the bound shortcut for mods and key, or nil.
local function hotkey(mods, key)
  for _, hk in ipairs(world.hotkeys) do
    if hk.mods == mods and hk.key == key and not hk.deleted then return hk end
  end
  return nil
end

-- press runs the shortcut for mods and key when it is bound and enabled.
local function press(mods, key)
  local hk = hotkey(mods, key)
  check("bound " .. mods .. "+" .. key, hk ~= nil)
  if hk and hk.enabled then hk.fn() end
end

-- enabledCount counts the shortcuts that are bound and enabled.
local function enabledCount()
  local n = 0
  for _, hk in ipairs(world.hotkeys) do
    if hk.enabled then n = n + 1 end
  end
  return n
end

-- action finds the Window menu entry for action name.
local function action(name, items)
  items = items or folder("Window")
  for _, it in ipairs(items) do
    if it.action == name then return it end
    if it.menu then
      local found = action(name, it.menu)
      if found then return found end
    end
  end
  return nil
end

-- laptop is a 1920 by 1080 display, too narrow to count as ultrawide.
local function laptop() return newScreen(1, 0, 1920, 1080) end

local channelHalf = { x = 512, y = 25, w = 1152, h = 1415 }

-- Test 66: Start binds Rectangle's keymap and every shortcut is on.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  check("t66 count", #world.hotkeys == 22, tostring(#world.hotkeys))
  check("t66 enabled", enabledCount() == 22, tostring(enabledCount()))
  check("t66 left", hotkey("ctrl+alt", "left") ~= nil)
  check("t66 displays", hotkey("ctrl+alt+cmd", "right") ~= nil)
  check("t66 restore", hotkey("ctrl+alt", "delete") ~= nil)
end

-- Test 67: Left half lands in the channel and repeats cycle 2/3, 1/3, then back to 1/2.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  focus(w)
  press("ctrl+alt", "left")
  frameIs("t67 half", w, channelHalf)
  press("ctrl+alt", "left")
  frameIs("t67 two thirds", w, { x = 512, y = 25, w = 1536, h = 1415 })
  press("ctrl+alt", "left")
  frameIs("t67 third", w, { x = 512, y = 25, w = 768, h = 1415 })
  press("ctrl+alt", "left")
  frameIs("t67 wrap", w, channelHalf)
  world.poll()
  frameIs("t67 layout keeps it", w, channelHalf)
end

-- Test 68: A window moved by hand between presses starts the cycle over.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  focus(w)
  press("ctrl+alt", "left")
  w.f = { x = 900, y = 100, w = 700, h = 500 }
  press("ctrl+alt", "left")
  frameIs("t68 half again", w, channelHalf)
  press("ctrl+alt", "right")
  frameIs("t68 right half", w, { x = 1664, y = 25, w = 1152, h = 1415 })
end

-- Test 69: On a screen that is not ultrawide nothing moves until a shortcut, which uses the
-- whole usable frame and moves a pin app too.
tests[#tests + 1] = function()
  install(laptop())
  local slack = addWin("Slack", { x = 500, y = 100, w = 900, h = 700 })
  anchors.start()
  world.poll()
  check("t69 untouched", slack.moves == 0)
  focus(slack)
  press("ctrl+alt", "left")
  frameIs("t69 half", slack, { x = 0, y = 25, w = 960, h = 1055 })
  press("ctrl+alt", "return")
  frameIs("t69 maximize", slack, { x = 0, y = 25, w = 1920, h = 1055 })
end

-- Test 70: A pinned window ignores shortcuts and the refusal is logged once.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  focus(slack)
  local before = slack.moves
  press("ctrl+alt", "right")
  press("ctrl+alt", "return")
  check("t70 not moved", slack.moves == before, "moves " .. slack.moves)
  check("t70 logged once", said("window actions leave pins alone") == 1)
end

-- Test 71: Restore returns the frame from before the first action and then does nothing.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  focus(w)
  press("ctrl+alt", "left")
  press("ctrl+alt", "c")
  press("ctrl+alt", "=")
  check("t71 undo enabled", item("Undo tidy").disabled == false)
  press("ctrl+alt", "delete")
  frameIs("t71 restored", w, { x = 1000, y = 200, w = 800, h = 600 })
  check("t71 nothing left", not anchors.canUndo())
  local moves = w.moves
  press("ctrl+alt", "delete")
  check("t71 second restore no-op", w.moves == moves)
  press("ctrl+alt", "left")
  frameIs("t71 cycle restarts", w, channelHalf)
end

-- Test 72: Drop anchor freezes shortcuts and grays out the Window entries.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  click("⚓ Drop anchor (freeze layout)")
  focus(w)
  press("ctrl+alt", "left")
  check("t72 frozen", w.moves == 0)
  check("t72 menu disabled", action("left-half").disabled == true)
  click("⚓ Weigh anchor (resume layout)")
  check("t72 menu enabled", action("left-half").disabled == false)
end

-- Test 73: Larger and smaller step 30 points and stop at the screen edge.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  focus(w)
  press("ctrl+alt", "=")
  frameIs("t73 larger", w, { x = 470, y = 270, w = 860, h = 560 })
  press("ctrl+alt", "-")
  frameIs("t73 smaller", w, { x = 500, y = 300, w = 800, h = 500 })
  press("ctrl+alt", "left")
  press("ctrl+alt", "=")
  frameIs("t73 curtain", w, { x = 0, y = 25, w = 990, h = 1055 })
end

-- Test 74: Display moves keep the relative frame, go from channel to laptop and back, and
-- wrap.
tests[#tests + 1] = function()
  local side = newScreen(2, 5120, 1512, 982)
  install(ultrawide(), side)
  local w = addWin("Safari", channelHalf)
  anchors.start()
  focus(w)
  press("ctrl+alt+cmd", "right")
  frameIs("t74 on laptop", w, { x = 5120, y = 25, w = 756, h = 957 })
  press("ctrl+alt+cmd", "left")
  frameIs("t74 back", w, channelHalf)
  press("ctrl+alt+cmd", "left")
  frameIs("t74 wraps", w, { x = 5120, y = 25, w = 756, h = 957 })
end

-- Test 75: A display move with one screen does nothing.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  focus(w)
  press("ctrl+alt+cmd", "right")
  check("t75 still", w.moves == 0)
end

-- Test 76: Ignore frontmost app turns shortcuts off while that app is in front, and back
-- on for other apps, and the choice survives reload.
tests[#tests + 1] = function()
  install(laptop())
  local zoom = addWin("Zoom", { x = 500, y = 300, w = 800, h = 500 })
  world.front = "Zoom"
  anchors.start()
  local it = item("Ignore frontmost app (Zoom)")
  check("t76 offered", it ~= nil and it.checked == false and it.disabled == false)
  click("Ignore frontmost app (Zoom)")
  check("t76 off", enabledCount() == 0, tostring(enabledCount()))
  check("t76 checked", item("Ignore frontmost app (Zoom)").checked == true)
  focus(zoom)
  for _, hk in ipairs(world.hotkeys) do
    if hk.key == "left" and hk.mods == "ctrl+alt" then hk.fn() end
  end
  world.front = "Safari"
  world.appWatch("Safari", 5)
  check("t76 on for others", enabledCount() == 22, tostring(enabledCount()))
  local settings = world.settings
  install(laptop())
  world.settings = settings
  world.front = "Zoom"
  anchors.start()
  check("t76 survives reload", enabledCount() == 0, tostring(enabledCount()))
  click("Ignore frontmost app (Zoom)")
  check("t76 unignored", enabledCount() == 22, tostring(enabledCount()))
end

-- Test 77: An app in ignoreBundles turns shortcuts off and its menu entry is fixed on.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.ignoreBundles = { "test.Zoom" }
  world.front = "Zoom"
  anchors.start()
  check("t77 off", enabledCount() == 0)
  local it = item("Ignore frontmost app (Zoom)")
  check("t77 fixed", it.checked == true and it.disabled == true)
  world.front = "Safari"
  world.appWatch("Safari", 4)
  check("t77 other events ignored", enabledCount() == 0)
  world.appWatch("Safari", 5)
  check("t77 on", enabledCount() == 22)
end

-- Test 78: Config overrides rebind and unbind keys and report bad entries.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.shortcuts = {
    ["left-half"] = { mods = { "ctrl", "alt" }, key = "h" },
    maximize = false,
    smaller = { mods = { "ctrl", "alt" }, key = "bogus" },
  }
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  check("t78 old key gone", hotkey("ctrl+alt", "left") == nil)
  check("t78 maximize gone", hotkey("ctrl+alt", "return") == nil)
  check("t78 bad key said", said("shortcut for smaller has an unknown key bogus") == 1)
  focus(w)
  press("ctrl+alt", "h")
  frameIs("t78 rebound", w, { x = 0, y = 25, w = 960, h = 1055 })
  check("t78 menu text", action("left-half").title == "Left half  ⌃⌥H", action("left-half").title)
  check("t78 menu no key", action("maximize").title == "Maximize")
end

-- Test 79: The menu is short at the top, and the Window folder runs actions and shows keys.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  focus(w)
  check("t79 top", titles(world.bar.menu()) == "⚓ Drop anchor (freeze layout),Re-moor now,-,"
    .. "Window,Locked apps,Widths,Workspaces,Settings,-,Reload", titles(world.bar.menu()))
  check("t79 families", titles(folder("Window")) == "Halves,Quarters,Thirds,Fourths,Grids,"
    .. "Size and move,Displays,Custom sizes,Organize", titles(folder("Window")))
  check("t79 no sizes", titles(item("Custom sizes").menu) == "No sizes in the config"
    and item("No sizes in the config").disabled == true)
  check("t79 settings", titles(folder("Settings")) == "Fullscreen fills the channel,"
    .. "Snap by dragging,Keymap,Ignore frontmost app (Safari),Icon,Edit config,Console", titles(folder("Settings")))
  check("t79 left text", action("left-half").title == "Left half  ⌃⌥←", action("left-half").title)
  action("bottom-right-sixth").fn()
  frameIs("t79 sixth", w, { x = 2048, y = 732, w = 768, h = 708 })
end

-- Test 80: A fullscreen window is left to the layout's fullscreen handling.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  w.full = true
  focus(w)
  press("ctrl+alt", "left")
  check("t80 untouched", w.moves == 0)
end

-- Test 81: Custom sizes show in their folder with shortcuts, run from the menu and the key,
-- and bad entries are reported at load.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.sizes = {
    { title = "Reading", x = 0.25, w = 0.5, shortcut = { mods = { "ctrl", "alt" }, key = "y" } },
    { title = "Video", width = 1280, height = 720 },
    { title = "Broken", w = 2 },
  }
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  focus(w)
  check("t81 folder", titles(item("Custom sizes").menu) == "Reading  ⌃⌥Y,Video",
    titles(item("Custom sizes").menu))
  check("t81 reported", said("size Broken needs x, y, w and h") == 1)
  press("ctrl+alt", "y")
  frameIs("t81 reading", w, { x = 1088, y = 25, w = 1152, h = 1415 })
  action("size:Video").fn()
  frameIs("t81 video", w, { x = 1024, y = 373, w = 1280, h = 720 })
  press("ctrl+alt", "delete")
  frameIs("t81 restore", w, { x = 1000, y = 200, w = 800, h = 600 })
end

-- Test 82: gapPx spaces halves, moves and resizes, and a bad gap is reported and ignored.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.gapPx = 10
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  focus(w)
  press("ctrl+alt", "left")
  frameIs("t82 left gap", w, { x = 10, y = 35, w = 945, h = 1035 })
  press("ctrl+alt", "=")
  frameIs("t82 larger keeps the gap edge", w, { x = 10, y = 35, w = 975, h = 1035 })
  press("ctrl+alt", "right")
  frameIs("t82 right gap", w, { x = 965, y = 35, w = 945, h = 1035 })
  press("ctrl+alt", "return")
  frameIs("t82 maximize gap", w, { x = 10, y = 35, w = 1900, h = 1035 })
  press("ctrl+alt", "-")
  frameIs("t82 smaller gap", w, { x = 40, y = 65, w = 1840, h = 975 })
  anchors.config.gapPx = -5
  press("ctrl+alt", "left")
  frameIs("t82 bad gap", w, { x = 0, y = 25, w = 960, h = 1055 })
  check("t82 said", said("gapPx must be a number from 0 to 100") == 1)
end

-- fire sends a mouse event of type t through the snap tap and checks it passes on.
local function fire(t)
  local passed = world.tap({
    getType = function() return t end,
    getFlags = function() return world.flags or {} end,
  })
  check("tap passes event " .. t, passed == false)
end

-- drag presses on win and drags it along path, moving it a little at each point unless
-- still is set. The button stays down.
local function drag(win, path, still)
  focus(win)
  fire(1)
  world.mousePos = path[1]
  fire(6)
  for _, p in ipairs(path) do
    if not still then
      win.f.x, win.f.y = win.f.x + 7, win.f.y + 3
    end
    world.mousePos = p
    fire(6)
  end
end

-- Test 83: Dragging to the left edge of a normal screen shows the footprint and snaps on
-- release.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  check("t83 tap", world.tapping == true and #world.tapTypes == 3)
  drag(w, { { x = 900, y = 500 }, { x = 0, y = 540 } })
  check("t83 footprint", world.canvas ~= nil and world.canvas.shown and world.canvas.lvl == "floating")
  frameIs("t83 footprint frame", { f = world.canvas.f }, { x = 0, y = 25, w = 960, h = 1055 })
  check("t83 not yet", w.moves == 0)
  fire(2)
  frameIs("t83 snapped", w, { x = 0, y = 25, w = 960, h = 1055 })
  check("t83 footprint gone", world.canvas == nil)
end

-- Test 84: On the ultrawide the strips snap into the channel.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  drag(w, { { x = 1300, y = 300 }, { x = 4000, y = 700 } })
  fire(2)
  frameIs("t84 right half", w, { x = 1664, y = 25, w = 1152, h = 1415 })
  drag(w, { { x = 2000, y = 300 }, { x = 200, y = 50 } })
  fire(2)
  frameIs("t84 top left", w, { x = 512, y = 25, w = 1152, h = 707 })
  drag(w, { { x = 1000, y = 300 }, { x = 1500, y = 1 } })
  fire(2)
  frameIs("t84 maximize", w, { x = 512, y = 25, w = 2304, h = 1415 })
end

-- Test 85: The footprint follows the zone and leaving every zone drops the snap.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  drag(w, { { x = 900, y = 500 }, { x = 0, y = 540 }, { x = 1919, y = 540 } })
  frameIs("t85 moved footprint", { f = world.canvas.f }, { x = 960, y = 25, w = 960, h = 1055 })
  check("t85 one canvas", world.canvases == 1)
  drag(w, { { x = 900, y = 500 }, { x = 0, y = 540 }, { x = 960, y = 540 } })
  check("t85 hidden", world.canvas == nil)
  local f = copy(w.f)
  fire(2)
  frameIs("t85 left where dropped", w, f)
end

-- Test 86: Dragging inside a window that never moves, or resizing one, never snaps.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  local path = {}
  for i = 1, 25 do path[i] = { x = 0, y = 540 } end
  drag(w, path, true)
  w.f.x = w.f.x + 50
  world.mousePos = { x = 0, y = 540 }
  fire(6)
  check("t86 no footprint", world.canvas == nil)
  fire(2)
  check("t86 still", w.moves == 0)
  focus(w)
  fire(1)
  world.mousePos = { x = 900, y = 500 }
  fire(6)
  w.f.x, w.f.w = w.f.x - 20, w.f.w + 20
  world.mousePos = { x = 0, y = 540 }
  fire(6)
  fire(6)
  check("t86 resize no footprint", world.canvas == nil)
  fire(2)
  check("t86 resize still", w.moves == 0)
end

-- Test 87: A pinned window never snaps.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  local before = slack.moves
  drag(slack, { { x = 200, y = 700 }, { x = 4000, y = 700 } })
  check("t87 no footprint", world.canvas == nil)
  fire(2)
  check("t87 not snapped", slack.moves == before)
end

-- Test 88: Unticking Snap by dragging or dropping anchor turns snapping off.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  check("t88 on by default", item("Snap by dragging").checked == true)
  click("Snap by dragging")
  check("t88 unchecked", item("Snap by dragging").checked == false)
  drag(w, { { x = 900, y = 500 }, { x = 0, y = 540 } })
  check("t88 no footprint", world.canvas == nil)
  fire(2)
  check("t88 off", w.moves == 0)
  click("Snap by dragging")
  click("⚓ Drop anchor (freeze layout)")
  drag(w, { { x = 900, y = 500 }, { x = 0, y = 540 } })
  fire(2)
  check("t88 frozen", w.moves == 0 and world.canvas == nil)
end

-- Test 89: Moving from a side bottom third to the center gives two thirds.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  drag(w, { { x = 900, y = 500 }, { x = 400, y = 1079 }, { x = 960, y = 1079 } })
  fire(2)
  frameIs("t89 two thirds", w, { x = 0, y = 25, w = 1280, h = 1055 })
end

-- Test 90: A drop on another display snaps to that display's area.
tests[#tests + 1] = function()
  local side = newScreen(2, 5120, 1512, 982)
  install(ultrawide(), side)
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  drag(w, { { x = 1300, y = 300 }, { x = 6631, y = 400 } })
  frameIs("t90 footprint", { f = world.canvas.f }, { x = 5876, y = 25, w = 756, h = 957 })
  fire(2)
  frameIs("t90 side right half", w, { x = 5876, y = 25, w = 756, h = 957 })
end

-- Test 91: An error inside the tap is logged, the event passes on, and the drag is dropped.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  drag(w, { { x = 900, y = 500 }, { x = 0, y = 540 } })
  hs.mouse.absolutePosition = function() error("mouse gone") end
  fire(6)
  check("t91 logged", said("mouse gone") == 1)
  check("t91 footprint gone", world.canvas == nil)
  fire(2)
  check("t91 no snap", w.moves == 0)
end

-- organize runs the Organize entry for action name.
local function organize(name)
  local it = action(name)
  check("organize has " .. name, it ~= nil)
  if it then it.fn() end
end

-- Test 92: Tile columns lays the channel's free windows side by side, leaves pins, and undoes.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local notes = addWin("Notes", { x = 2000, y = 100, w = 400, h = 400 })
  local chrome = addWin("Chrome", { x = 700, y = 100, w = 400, h = 400 })
  local safari = addWin("Safari", { x = 1500, y = 100, w = 400, h = 400 })
  anchors.start()
  local before = slack.moves
  focus(safari)
  organize("tile-columns")
  frameIs("t92 chrome", chrome, { x = 512, y = 25, w = 768, h = 1415 })
  frameIs("t92 safari", safari, { x = 1280, y = 25, w = 768, h = 1415 })
  frameIs("t92 notes", notes, { x = 2048, y = 25, w = 768, h = 1415 })
  check("t92 pin kept", slack.moves == before)
  click("Undo tidy")
  frameIs("t92 undone", safari, { x = 1500, y = 100, w = 400, h = 400 })
end

-- Test 93: Tile rows stacks by height order and tile all builds a grid on a laptop.
tests[#tests + 1] = function()
  install(laptop())
  local a = addWin("Notes", { x = 100, y = 600, w = 400, h = 300 })
  local b = addWin("Safari", { x = 300, y = 100, w = 400, h = 300 })
  local c = addWin("Chrome", { x = 900, y = 100, w = 400, h = 300 })
  anchors.start()
  focus(b)
  organize("tile-rows")
  frameIs("t93 b top", b, { x = 0, y = 25, w = 1920, h = 351 })
  frameIs("t93 c middle", c, { x = 0, y = 376, w = 1920, h = 352 })
  frameIs("t93 a bottom", a, { x = 0, y = 728, w = 1920, h = 352 })
  a.f = { x = 100, y = 600, w = 400, h = 300 }
  b.f = { x = 300, y = 100, w = 400, h = 300 }
  c.f = { x = 900, y = 100, w = 400, h = 300 }
  organize("tile-all")
  frameIs("t93 grid b", b, { x = 0, y = 25, w = 960, h = 527 })
  frameIs("t93 grid c", c, { x = 960, y = 25, w = 960, h = 527 })
  frameIs("t93 grid a", a, { x = 0, y = 552, w = 1920, h = 528 })
end

-- Test 94: Cascade all stacks back-most first so the front-most window ends on top.
tests[#tests + 1] = function()
  install(laptop())
  local back = addWin("Notes", { x = 900, y = 300, w = 600, h = 400 })
  local mid = addWin("Chrome", { x = 500, y = 500, w = 700, h = 500 })
  local front = addWin("Safari", { x = 100, y = 100, w = 800, h = 600 })
  anchors.start()
  focus(front)
  organize("cascade-all")
  frameIs("t94 back", back, { x = 0, y = 25, w = 600, h = 400 })
  frameIs("t94 mid", mid, { x = 30, y = 55, w = 700, h = 500 })
  frameIs("t94 front", front, { x = 60, y = 85, w = 800, h = 600 })
end

-- Test 95: Cascade active app moves only the focused app's windows.
tests[#tests + 1] = function()
  install(laptop())
  local other = addWin("Chrome", { x = 500, y = 500, w = 700, h = 500 })
  local s1 = addWin("Safari", { x = 900, y = 300, w = 600, h = 400 })
  local s2 = addWin("Safari", { x = 100, y = 100, w = 800, h = 600 })
  anchors.start()
  focus(s2)
  organize("cascade-active-app")
  frameIs("t95 s1", s1, { x = 0, y = 25, w = 600, h = 400 })
  frameIs("t95 s2", s2, { x = 30, y = 55, w = 800, h = 600 })
  check("t95 other", other.moves == 0)
end

-- Test 96: Cycle stacked windows walks the windows sharing a frame both ways and wraps.
tests[#tests + 1] = function()
  install(laptop())
  local stack = { x = 0, y = 25, w = 960, h = 1055 }
  local a = addWin("Notes", stack)
  local b = addWin("Chrome", stack)
  local c = addWin("Safari", stack)
  addWin("Mail", { x = 960, y = 25, w = 960, h = 1055 })
  anchors.start()
  focus(b)
  organize("cycle-stacked-windows")
  check("t96 next", world.focused == c)
  organize("cycle-stacked-windows")
  check("t96 wrap", world.focused == a)
  organize("cycle-stacked-windows-backward")
  check("t96 back", world.focused == c)
  check("t96 none moved", a.moves + b.moves + c.moves == 0)
  local lone = addWin("Maps", { x = 400, y = 400, w = 300, h = 300 })
  focus(lone)
  organize("cycle-stacked-windows")
  check("t96 alone", world.focused == lone)
end

-- Test 97: Reverse all mirrors the channel's free windows and leaves pins.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local w = addWin("Safari", channelHalf)
  anchors.start()
  local before = slack.moves
  focus(w)
  organize("reverse-all")
  frameIs("t97 mirrored", w, { x = 1664, y = 25, w = 1152, h = 1415 })
  check("t97 pin kept", slack.moves == before)
end

-- Test 98: Organize does nothing while frozen, and takes shortcuts from the config.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.shortcuts = { ["tile-all"] = { mods = { "ctrl", "alt" }, key = "a" } }
  local a = addWin("Notes", { x = 100, y = 600, w = 400, h = 300 })
  local b = addWin("Safari", { x = 300, y = 100, w = 400, h = 300 })
  anchors.start()
  focus(b)
  click("⚓ Drop anchor (freeze layout)")
  check("t98 disabled", action("tile-all").disabled == true)
  press("ctrl+alt", "a")
  check("t98 frozen", a.moves + b.moves == 0)
  click("⚓ Weigh anchor (resume layout)")
  check("t98 menu key", action("tile-all").title == "Tile all  ⌃⌥A", action("tile-all").title)
  press("ctrl+alt", "a")
  frameIs("t98 tiled", b, { x = 0, y = 25, w = 960, h = 1055 })
end

-- Test 99: Tidy works on a normal screen through the focused window, and does nothing unfocused.
tests[#tests + 1] = function()
  install(laptop())
  local a = addWin("Notes", { x = 900, y = 300, w = 400, h = 300 })
  local b = addWin("Safari", { x = 100, y = 100, w = 400, h = 300 })
  anchors.start()
  local tidy = item("Tidy channel").menu
  item("Halves", tidy).fn()
  check("t99 unfocused", a.moves + b.moves == 0)
  focus(b)
  item("Halves", tidy).fn()
  frameIs("t99 left", b, { x = 0, y = 25, w = 960, h = 1055 })
  frameIs("t99 right", a, { x = 960, y = 25, w = 960, h = 1055 })
end

-- Test 100: Tiles honor gapPx.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.gapPx = 10
  local a = addWin("Notes", { x = 900, y = 300, w = 400, h = 300 })
  local b = addWin("Safari", { x = 100, y = 100, w = 400, h = 300 })
  anchors.start()
  focus(b)
  organize("tile-columns")
  frameIs("t100 left", b, { x = 10, y = 35, w = 945, h = 1035 })
  frameIs("t100 right", a, { x = 965, y = 35, w = 945, h = 1035 })
end

-- Test 101: The Organize folder lists the organize actions, then fill, tidy and undo.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  check("t101 titles", titles(item("Organize").menu) == "Tile columns,Tile rows,Tile all,"
    .. "Cascade all,Cascade active app,Cycle stacked windows,Cycle stacked windows backward,"
    .. "Reverse all,-,Fill channel,Tidy channel,Undo tidy", titles(item("Organize").menu))
end

-- mouseTap returns the mouse button tap, or nil.
local function mouseTap()
  for _, tap in ipairs(world.taps) do
    if tap.types[1] == 25 and tap.running then return tap end
  end
  return nil
end

-- click sends mouse button event type t for button through the button tap.
local function button(t, n)
  return mouseTap().fn({ getType = function() return t end, getProperty = function() return n end })
end

-- Test 102: A moorings link runs an action, a custom size or nothing for an unknown name.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.sizes = { { title = "Video", width = 1280, height = 720 } }
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  focus(w)
  check("t102 bound", world.urls.moorings ~= nil)
  world.urls.moorings("moorings", { action = "left-half" })
  frameIs("t102 left", w, { x = 0, y = 25, w = 960, h = 1055 })
  world.urls.moorings("moorings", { action = "size:Video" })
  frameIs("t102 size", w, { x = 320, y = 193, w = 1280, h = 720 })
  local moves = w.moves
  world.urls.moorings("moorings", { action = "sideways" })
  world.urls.moorings("moorings", {})
  check("t102 unknown", w.moves == moves and said("unknown action sideways") == 1
    and said("unknown action nil") == 1)
  click("⚓ Drop anchor (freeze layout)")
  world.urls.moorings("moorings", { action = "maximize" })
  check("t102 frozen", w.moves == moves)
end

-- Test 103: Settings, Keymap switches to Spectacle's keys live and the choice survives reload.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  check("t103 rectangle", item("Rectangle").checked == true and item("Spectacle").checked == false)
  click("Spectacle")
  check("t103 checked", item("Spectacle").checked == true)
  check("t103 old gone", hotkey("ctrl+alt", "return") == nil)
  focus(w)
  press("alt+cmd", "left")
  frameIs("t103 left", w, { x = 0, y = 25, w = 960, h = 1055 })
  press("ctrl+alt", "left")
  frameIs("t103 previous third", w, { x = 1280, y = 25, w = 640, h = 1055 })
  check("t103 menu text", action("left-half").title == "Left half  ⌥⌘←", action("left-half").title)
  local settings = world.settings
  install(laptop())
  world.settings = settings
  anchors.start()
  check("t103 survives", hotkey("alt+cmd", "left") ~= nil and hotkey("ctrl+alt", "return") == nil)
end

-- Test 104: The config keymap applies until a menu choice, and an unknown one falls back.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.keymap = "spectacle"
  anchors.start()
  check("t104 config", hotkey("alt+cmd", "f") ~= nil)
  install(laptop())
  anchors.config.keymap = "vim"
  anchors.start()
  check("t104 fallback", hotkey("ctrl+alt", "return") ~= nil)
  check("t104 said", said("keymap vim is unknown: using rectangle") == 1)
end

-- Test 105: Bound mouse buttons run their action and swallow their events, and everything
-- else passes on.
tests[#tests + 1] = function()
  install(newScreen(1, 0, 1920, 1080), newScreen(2, 1920, 1920, 1080))
  anchors.config.mouseButtons = { [3] = "maximize", [4] = "next-display", [9] = "sideways" }
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  check("t105 tap", mouseTap() ~= nil)
  check("t105 said", said("unknown action sideways for button 9") == 1)
  focus(w)
  check("t105 down swallowed", button(25, 3) == true)
  frameIs("t105 maximized", w, { x = 0, y = 25, w = 1920, h = 1055 })
  check("t105 up swallowed", button(26, 3) == true)
  button(25, 4)
  frameIs("t105 next display", w, { x = 1920, y = 25, w = 1920, h = 1055 })
  button(26, 4)
  frameIs("t105 up runs nothing", w, { x = 1920, y = 25, w = 1920, h = 1055 })
  local moves = w.moves
  check("t105 unbound passes", button(25, 2) == false)
  click("⚓ Drop anchor (freeze layout)")
  check("t105 frozen passes", button(25, 3) == false and w.moves == moves)
  click("⚓ Weigh anchor (resume layout)")
  world.front = "Zoom"
  anchors.toggleShortcutIgnore("test.Zoom")
  check("t105 ignored passes", button(25, 3) == false and w.moves == moves)
end

-- Test 106: No mouse buttons means no button tap, and an error in the tap passes the event on.
tests[#tests + 1] = function()
  install(laptop())
  anchors.start()
  check("t106 no tap", mouseTap() == nil)
  install(laptop())
  anchors.config.mouseButtons = { [3] = "maximize" }
  anchors.start()
  local passed = mouseTap().fn({ getType = function() return 25 end,
    getProperty = function() error("no button") end })
  check("t106 error passes", passed == false and said("no button") == 1)
  click("Spectacle")
  local running = 0
  for _, tap in ipairs(world.taps) do
    if tap.types[1] == 25 and tap.running then running = running + 1 end
  end
  check("t106 one tap after rebind", running == 1, tostring(running))
end

-- Test 107: Option-dropping a window on a strip half parks its app in that slot.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", rightFull)
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  world.flags = { alt = true }
  drag(w, { { x = 1300, y = 300 }, { x = 4000, y = 1000 } })
  frameIs("t107 footprint", { f = world.canvas.f }, rightBottom)
  fire(2)
  check("t107 slot", anchors.assignments()["right-bottom"] == "test.Safari")
  frameIs("t107 parked", w, rightBottom)
  frameIs("t107 iterm top", term, rightTop)
  check("t107 row", item("Right bottom: Safari") ~= nil)
end

-- Test 108: Option over the channel neither parks nor snaps, and Option on a normal screen
-- snaps as usual.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  world.flags = { alt = true }
  drag(w, { { x = 1300, y = 300 }, { x = 1500, y = 1 } })
  check("t108 no footprint", world.canvas == nil)
  local f = copy(w.f)
  fire(2)
  frameIs("t108 left alone", w, f)
  check("t108 no slot", world.settings["moorings.slots"] == nil)
  install(laptop())
  local l = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  world.flags = { alt = true }
  drag(l, { { x = 900, y = 500 }, { x = 0, y = 540 } })
  fire(2)
  frameIs("t108 laptop snap", l, { x = 0, y = 25, w = 960, h = 1055 })
end

-- Test 109: A pinned window can be parked in another slot but never snaps.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  world.flags = { alt = true }
  drag(slack, { { x = 200, y = 300 }, { x = 4000, y = 200 } })
  fire(2)
  check("t109 moved slot", anchors.assignments()["right-top"] == "com.tinyspeck.slackmacgap"
    and anchors.assignments()["left-top"] == "")
  world.flags = {}
  local before = slack.moves
  drag(slack, { { x = 4000, y = 300 }, { x = 1500, y = 1 } })
  check("t109 no snap footprint", world.canvas == nil)
  fire(2)
  check("t109 no snap", slack.moves == before)
end

-- Test 110: An ignored app cannot be parked.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.ignoreBundles = { "test.Zoom" }
  local z = addWin("Zoom", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  world.flags = { alt = true }
  drag(z, { { x = 1300, y = 300 }, { x = 200, y = 200 } })
  check("t110 no footprint", world.canvas == nil)
  fire(2)
  check("t110 no slot", world.settings["moorings.slots"] == nil)
end

-- save names the current layout through the Save current layout prompt.
local function saveAs(name)
  world.prompt = { "Save", name }
  click("Save current layout…")
end

-- Test 111: A workspace puts back the slots, widths and free window frames.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local safari = addWin("Safari", { x = 600, y = 100, w = 900, h = 700 })
  local chrome = addWin("Chrome", { x = 1600, y = 300, w = 1000, h = 800 })
  addWin("Notes", { x = 2000, y = 200, w = 400, h = 400 })
  anchors.start()
  check("t111 empty", item("No saved workspaces") ~= nil)
  saveAs("  Coding ")
  check("t111 prompt", world.hsFocused and world.promptArgs[1] == "Save workspace")
  check("t111 listed", item("Coding") ~= nil and item("No saved workspaces") == nil)
  click("Left 20%, right 40%")
  pick("Left bottom: Empty", "Notes")
  safari.f = { x = 1100, y = 50, w = 500, h = 500 }
  chrome.f = { x = 1100, y = 600, w = 500, h = 500 }
  focus(safari)
  click("Recall")
  local l, r = anchors.widths()
  check("t111 widths", l == 10 and r == 45)
  check("t111 slots", anchors.assignments()["left-bottom"] == "")
  frameIs("t111 slack", slack, leftFull)
  frameIs("t111 safari", safari, { x = 600, y = 100, w = 900, h = 700 })
  frameIs("t111 chrome", chrome, { x = 1600, y = 300, w = 1000, h = 800 })
  press("ctrl+alt", "delete")
  frameIs("t111 restore", safari, { x = 1100, y = 50, w = 500, h = 500 })
end

-- Test 112: Windows of one app go back by title, and a missing app is reported.
tests[#tests + 1] = function()
  install(laptop())
  local docs = addWin("Safari", { x = 0, y = 25, w = 900, h = 700 })
  docs.name = "Docs"
  local mail = addWin("Safari", { x = 1000, y = 25, w = 900, h = 700 })
  mail.name = "Mail"
  addWin("Notes", { x = 100, y = 800, w = 300, h = 200 })
  anchors.start()
  focus(docs)
  saveAs("Two")
  docs.f, mail.f = copy(mail.f), copy(docs.f)
  table.remove(world.windows, 1)
  anchors.recallWorkspace("Two")
  frameIs("t112 docs", docs, { x = 0, y = 25, w = 900, h = 700 })
  frameIs("t112 mail", mail, { x = 1000, y = 25, w = 900, h = 700 })
  check("t112 missed", said("workspace Two: 1 windows had no running app or display") == 1)
end

-- Test 113: A workspace tied to a display setup comes back when that setup is plugged in.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Safari", { x = 600, y = 100, w = 900, h = 700 })
  anchors.start()
  saveAs("Desk")
  click("Recall when these displays connect")
  check("t113 tied", item("Recall when these displays connect").checked == true)
  local wide = world.screens[1]
  world.screens = { newScreen(2, 0, 1512, 982) }
  w.f = { x = 100, y = 100, w = 900, h = 700 }
  world.onScreens()
  frameIs("t113 no recall on laptop", w, { x = 100, y = 100, w = 900, h = 700 })
  check("t113 not tied here", item("Recall when these displays connect").checked == false)
  world.screens = { wide }
  w.f = { x = 1000, y = 300, w = 900, h = 700 }
  world.onScreens()
  frameIs("t113 recalled", w, { x = 600, y = 100, w = 900, h = 700 })
  w.f = { x = 1000, y = 300, w = 900, h = 700 }
  world.onScreens()
  frameIs("t113 same setup no repeat", w, { x = 1000, y = 300, w = 900, h = 700 })
  pick("Desk", "Replace with current layout")
  check("t113 replace keeps tie", item("Recall when these displays connect").checked == true)
  click("Recall when these displays connect")
  check("t113 untied", item("Recall when these displays connect").checked == false)
end

-- Test 114: Tying a second workspace to a setup unties the first, and a reload recalls nothing.
tests[#tests + 1] = function()
  install(ultrawide())
  addWin("Safari", { x = 600, y = 100, w = 900, h = 700 })
  anchors.start()
  saveAs("A")
  saveAs("B")
  pick("A", "Recall when these displays connect")
  pick("B", "Recall when these displays connect")
  check("t114 a untied", item("Recall when these displays connect", item("A").menu).checked == false)
  check("t114 b tied", item("Recall when these displays connect", item("B").menu).checked == true)
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  local w2 = addWin("Safari", { x = 1000, y = 300, w = 900, h = 700 })
  anchors.start()
  world.onScreens()
  frameIs("t114 no recall on reload", w2, { x = 1000, y = 300, w = 900, h = 700 })
end

-- Test 115: Replace, Delete, a canceled or blank name, and a frozen layout.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  focus(w)
  world.prompt = { "Cancel", "Nope" }
  click("Save current layout…")
  world.prompt = { "Save", "   " }
  click("Save current layout…")
  check("t115 nothing saved", item("No saved workspaces") ~= nil)
  saveAs("Main")
  w.f = { x = 500, y = 300, w = 600, h = 400 }
  pick("Main", "Replace with current layout")
  w.f = { x = 0, y = 25, w = 300, h = 300 }
  click("⚓ Drop anchor (freeze layout)")
  check("t115 recall disabled", item("Recall").disabled == true)
  anchors.recallWorkspace("Main")
  frameIs("t115 frozen", w, { x = 0, y = 25, w = 300, h = 300 })
  click("⚓ Weigh anchor (resume layout)")
  click("Recall")
  frameIs("t115 replaced", w, { x = 500, y = 300, w = 600, h = 400 })
  pick("Main", "Delete")
  check("t115 deleted", item("No saved workspaces") ~= nil)
end

-- Test 116: A workspace runs from a shortcut or a link, and an unknown one is reported.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.shortcuts = { ["workspace:Main"] = { mods = { "ctrl", "alt" }, key = "1" } }
  local w = addWin("Safari", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  focus(w)
  saveAs("Main")
  w.f = { x = 500, y = 300, w = 600, h = 400 }
  press("ctrl+alt", "1")
  frameIs("t116 shortcut", w, { x = 100, y = 100, w = 900, h = 700 })
  w.f = { x = 500, y = 300, w = 600, h = 400 }
  world.urls.moorings("moorings", { action = "workspace:Main" })
  frameIs("t116 link", w, { x = 100, y = 100, w = 900, h = 700 })
  world.urls.moorings("moorings", { action = "workspace:Gone" })
  check("t116 unknown", said("no workspace is named Gone") == 1)
  world.urls.moorings("moorings", { action = "workspace:" })
  check("t116 empty name", said("unknown action workspace:") == 1)
end

-- Test 117: A saved window whose display is gone stays where it is.
tests[#tests + 1] = function()
  local side = newScreen(2, 5120, 1512, 982)
  install(ultrawide(), side)
  local w = addWin("Safari", { x = 5300, y = 100, w = 800, h = 600 })
  anchors.start()
  focus(w)
  saveAs("Two screens")
  world.screens = { world.screens[1] }
  w.f = { x = 1000, y = 200, w = 800, h = 600 }
  anchors.recallWorkspace("Two screens")
  frameIs("t117 stays", w, { x = 1000, y = 200, w = 800, h = 600 })
  check("t117 said", said("1 windows had no running app or display") == 1)
end

-- Test 118: A saved workspace with widths that leave no channel keeps the widths in effect.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  click("Left 20%, right 40%")
  anchors.assign("left-bottom", "test.Notes")
  world.settings["moorings.workspaces"] = { Bad = { left = 60, right = 45, windows = {} } }
  anchors.recallWorkspace("Bad")
  local l, r = anchors.widths()
  check("t118 kept", l == 20 and r == 40, l .. " " .. r)
  check("t118 slots kept", anchors.assignments()["left-bottom"] == "test.Notes")
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
