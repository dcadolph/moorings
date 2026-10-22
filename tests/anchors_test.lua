-- anchors_test drives anchors.lua against a fake Hammerspoon. Run it from the
-- repo root with: lua tests/anchors_test.lua

package.path = "./?.lua;" .. package.path

local realPrint = print
-- markPath is where the moorings mark loads from in the fake Hammerspoon.
local markPath = "/tmp/hammerspoon/moorings/mark.svg"
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

-- Win:setFrame moves the window and counts the move. A window with minW or minH keeps
-- its origin and stays at least that size, as apps with a minimum size do.
function Win:setFrame(f)
  self.f = copy(f)
  self.f.w = math.max(self.f.w, self.minW or 0)
  self.f.h = math.max(self.f.h, self.minH or 0)
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
    name = function() return name end,
    mainWindow = function()
      for _, w in ipairs(world.windows) do
        if w.app == name and not w.secondary then return w end
      end
      return win
    end,
  }
end

-- Win:zoomButtonRect returns the green button rect, 57 points in and 11 down.
function Win:zoomButtonRect()
  self.zoomAsks = (self.zoomAsks or 0) + 1
  return { x = self.f.x + 57, y = self.f.y + 11, w = 16, h = 16 }
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
    screens = { ... }, windows = {}, settings = {}, nextID = 0, printed = {}, apps = {}, opened = {},
    clock = 1000, mouseDown = false, trusted = true, hotkeys = {}, taps = {}, urls = {},
    dirs = {}, images = { [markPath] = true }, notices = {},
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
    json = { encode = function(t) world.model = t return "{}" end },
    webview = {
      new = function(rect, prefs, content)
        local v = { rect = rect, prefs = prefs, content = content }
        for _, m in ipairs({ "windowStyle", "windowTitle", "allowTextEntry", "deleteOnClose", "html",
          "show", "bringToFront" }) do
          v[m] = function(self, arg) self[m .. "Arg"] = arg self[m .. "Calls"] = (self[m .. "Calls"] or 0) + 1 return self end
        end
        function v:windowCallback(fn) self.onWindow = fn return self end
        function v:evaluateJavaScript(js) world.js = js return self end
        world.view, world.views = v, (world.views or 0) + 1
        return v
      end,
      usercontent = {
        new = function(name)
          local u = { name = name }
          function u:setCallback(fn) world.webMsg = fn return self end
          return u
        end,
      },
    },
    dialog = {
      chooseFileOrFolder = function(...)
        world.chooseArgs = { ... }
        return world.chosenFile
      end,
      textPrompt = function(...)
        world.promptArgs, world.focusedAtPrompt = { ... }, world.hsFocused == true
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
    fs = {
      attributes = function(path) return world.dirs[path] and "directory" or nil end,
      dir = function(path)
        if not world.dirs[path] then error("can't open " .. path) end
        local files, i = world.dirs[path], 0
        return function() i = i + 1 return files[i] end, {}
      end,
    },
    image = {
      imageFromPath = function(path)
        if not world.images[path] then return nil end
        local img = { path = path }
        function img:setSize(size) self.size = size return self end
        function img:template(on) self.isTemplate = on return self end
        return img
      end,
    },
    notify = {
      new = function(fn, attrs)
        local n = { fn = fn, attrs = attrs }
        function n:send() self.sent = true return self end
        function n:withdraw() self.withdrawn = true return self end
        world.notices[#world.notices + 1] = n
        return n
      end,
    },
    task = {
      new = function(path, _, args)
        local t = {}
        function t:start()
          world.opened[#world.opened + 1] = path .. " " .. table.concat(args, " ")
          return self
        end
        return t
      end,
    },
    openConsole = function() world.console = true end,
    reload = function() world.reloaded = true end,
    execute = function(cmd) world.executed = cmd end,
    alert = { show = function(msg) world.alerted, world.alerts = msg, (world.alerts or 0) + 1 end },
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
      infoForBundlePath = function(path)
        local name = path:match("/([^/]+)%.app$")
        return name and { CFBundleIdentifier = bundleFor(name) } or {}
      end,
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
      mainScreen = function() return world.screens[1] end,
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
        function bar:setTitle(t) self.title, self.titleCalls = t, (self.titleCalls or 0) + 1 return self end
        function bar:setIcon(i, t) self.icon, self.iconTemplate = i, t return self end
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
  for _, name in ipairs({ "actions", "snap", "tile", "workspaces", "settings" }) do
    package.loaded[name] = nil
  end
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

-- markShown reports whether the menu bar shows the moorings mark, the default icon, from
-- wherever anchors.path points.
local function markShown()
  local icon = world.bar.icon
  return world.bar.title == nil and icon ~= nil and icon.path:find("/mark%.svg$") ~= nil
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
  check("t1 title", markShown())
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

-- Test 4: Slack does not expand on focus by default. With expandPct 30, focusing it
-- expands it to 30 percent and focusing another app collapses it.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", { x = 0, y = 25, w = 512, h = 1415 })
  local other = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  focus(slack)
  world.onEvent()
  frameIs("t4 default stays", slack, { x = 0, y = 25, w = 512, h = 1415 })
  anchors.config.pins[1].expandPct = 30
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
  click("⚓ Raise anchor (let windows drift)")
  local w = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  world.poll()
  check("t7 frozen", w.moves == 0)
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  anchors.start()
  check("t7 survives reload", item("⚓ Drop anchor (hold the layout)") ~= nil)
  local w2 = addWin("Safari", { x = 0, y = 25, w = 800, h = 600 })
  world.poll()
  check("t7 still frozen", w2.moves == 0)
  click("⚓ Drop anchor (hold the layout)")
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
  local logged = false
  for _, line in ipairs(world.printed) do
    if line:find("boom", 1, true) then logged = true end
  end
  check("t18 logged", logged)
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

-- Test 22: The Slack pin leaves Slack's other windows where they are.
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
  click("⚓ Raise anchor (let windows drift)")
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

-- Test 44: Each stacked pin holds its app's main window and leaves the other windows alone.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left" },
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
  check("t44 notes second stays", n2.moves == 0)
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
  for _, it in ipairs(folder("Anchored apps")) do
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
  check("t46 choices", titles(choices) == "Empty,iTerm2,Safari,Slack,-,Choose app…", titles(choices))
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

-- Test 49: A chosen app keeps its config expandPct, others get none, and each holds one window.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local huddle = addWin("Slack", { x = 1200, y = 200, w = 400, h = 300 })
  huddle.secondary = true
  local n1 = addWin("Notes", { x = 1000, y = 200, w = 400, h = 400 })
  local n2 = addWin("Notes", { x = 1500, y = 300, w = 500, h = 400 })
  n2.secondary = true
  anchors.config.pins[1].expandPct = 30
  anchors.start()
  pick("Left bottom: Empty", "Notes")
  check("t49 huddle stays", huddle.moves == 0)
  focus(slack)
  world.onEvent()
  frameIs("t49 slack expanded", slack, { x = 0, y = 25, w = 1536, h = 707 })
  focus(n1)
  world.onEvent()
  frameIs("t49 notes not expanded", n1, leftBottom)
  check("t49 notes second window stays", n2.moves == 0)
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

-- Test 51: Anchor frontmost app puts the app last used in the chosen slot.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", rightFull)
  local safari = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  world.front = "Safari"
  anchors.start()
  local fast = item("Anchor frontmost app (Safari)")
  check("t51 enabled", fast ~= nil and fast.disabled == false)
  pick("Anchor frontmost app (Safari)", "Right bottom")
  frameIs("t51 safari right bottom", safari, rightBottom)
  frameIs("t51 iterm right top", term, rightTop)
  local target = item("Right bottom", item("Anchor frontmost app (Safari)").menu)
  check("t51 checked", target.checked == true)
end

-- Test 52: Anchor frontmost app is disabled for an ignored app.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.ignoreBundles = { "test.Zoom" }
  world.front = "Zoom"
  anchors.start()
  check("t52 disabled", item("Anchor frontmost app (Zoom)").disabled == true)
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
  check("t54 choices", titles(choices) == "Empty,Safari,-,Choose app…", titles(choices))
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
  press("ctrl+alt", "c")
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
  click("⚓ Raise anchor (let windows drift)")
  focus(w)
  press("ctrl+alt", "left")
  check("t72 frozen", w.moves == 0)
  check("t72 menu disabled", action("left-half").disabled == true)
  click("⚓ Drop anchor (hold the layout)")
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
  check("t79 top", titles(world.bar.menu()) == "⚓ Raise anchor (let windows drift),Re-moor now,-,"
    .. "Window,Lift,Anchored apps,Widths,Heights,Workspaces,Settings,-,Reload", titles(world.bar.menu()))
  check("t79 families", titles(folder("Window")) == "Halves,Quarters,Thirds,Fourths,Grids,"
    .. "Size and move,Displays,Custom sizes,Organize", titles(folder("Window")))
  check("t79 no sizes", titles(item("Custom sizes").menu) == "No sizes in the config"
    and item("No sizes in the config").disabled == true)
  check("t79 settings", titles(folder("Settings")) == "Settings window…,-,Fullscreen fills the channel,"
    .. "Fullscreen keeps anchored apps in their slots,Snap by dragging,Keymap,Ignore frontmost app (Safari),Icon,Edit config,Console", titles(folder("Settings")))
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
  click("⚓ Raise anchor (let windows drift)")
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
  click("⚓ Raise anchor (let windows drift)")
  check("t98 disabled", action("tile-all").disabled == true)
  press("ctrl+alt", "a")
  check("t98 frozen", a.moves + b.moves == 0)
  click("⚓ Drop anchor (hold the layout)")
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
  click("⚓ Raise anchor (let windows drift)")
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
  click("⚓ Raise anchor (let windows drift)")
  check("t105 frozen passes", button(25, 3) == false and w.moves == moves)
  click("⚓ Drop anchor (hold the layout)")
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
  click("⚓ Raise anchor (let windows drift)")
  check("t115 recall disabled", item("Recall").disabled == true)
  anchors.recallWorkspace("Main")
  frameIs("t115 frozen", w, { x = 0, y = 25, w = 300, h = 300 })
  click("⚓ Drop anchor (hold the layout)")
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

-- openSettings opens the settings window from the repo copy of the page and
-- sends its ready message.
local function openSettings()
  anchors.path = function(file) return "./" .. file end
  world.images["./mark.svg"] = true
  click("Settings window…")
  world.webMsg({ body = { type = "ready" } })
end

-- send posts message m from the settings window.
local function send(m)
  world.webMsg({ body = m })
end

-- modelRow finds the shortcuts row for action name in the last model sent.
local function modelRow(name)
  for _, g in ipairs(world.model.groups) do
    for _, a in ipairs(g.actions) do
      if a.name == name then return a end
    end
  end
  return nil
end

-- Test 119: The settings window opens once, loads the page and gets the model on ready.
tests[#tests + 1] = function()
  install(laptop())
  anchors.start()
  openSettings()
  local v = world.view
  check("t119 page", v.htmlArg ~= nil and v.htmlArg:find("moorings settings", 1, true) ~= nil)
  check("t119 window", v.windowTitleArg == "moorings settings" and v.allowTextEntryArg == true
    and v.showCalls == 1 and world.hsFocused)
  check("t119 handler", v.content.name == "moorings")
  check("t119 rendered", world.js == "moorings.render({})")
  local titlesSeen = {}
  for _, g in ipairs(world.model.groups) do titlesSeen[#titlesSeen + 1] = g.title end
  check("t119 groups", table.concat(titlesSeen, ",") == "Halves,Quarters,Thirds,Fourths,"
    .. "Grids, Sixths,Grids, Eighths,Grids, Ninths,Grids, Corner thirds,Size and move,Displays,"
    .. "Custom sizes,Organize", table.concat(titlesSeen, ","))
  local row = modelRow("left-half")
  check("t119 row", row.label == "Left half" and row.key == "⌃⌥←" and row.source == "default")
  check("t119 general", world.model.keymap == "rectangle" and world.model.snap == true
    and world.model.gap == 0)
  click("Settings window…")
  check("t119 one window", world.views == 1 and v.showCalls == 2)
end

-- Test 120: Recording suspends every shortcut and stopping turns them back on.
tests[#tests + 1] = function()
  install(laptop())
  anchors.start()
  openSettings()
  send({ type = "record", on = true })
  check("t120 off", enabledCount() == 0)
  send({ type = "record", on = false })
  check("t120 on", enabledCount() == 22)
  send({ type = "record", on = true })
  world.view.onWindow("closing")
  check("t120 close turns on", enabledCount() == 22)
  local printed = #world.printed
  send({ type = "ready" })
  check("t120 late message quiet", #world.printed == printed)
  click("Settings window…")
  check("t120 reopens", world.views == 2)
end

-- Test 121: A recorded key rebinds an action, survives reload, and Reset and Clear work.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  openSettings()
  send({ type = "record", on = true })
  send({ type = "bind", action = "left-half", code = "KeyH", ctrl = true, alt = true })
  check("t121 bound", hotkey("ctrl+alt", "h") ~= nil and hotkey("ctrl+alt", "left") == nil)
  check("t121 on again", enabledCount() == 22, tostring(enabledCount()))
  check("t121 notice", world.model.notice == "Left half is now ⌃⌥H.", world.model.notice)
  check("t121 source", modelRow("left-half").source == "saved" and modelRow("left-half").key == "⌃⌥H")
  check("t121 notice clears", (function() send({ type = "ready" }) return world.model.notice == "" end)())
  focus(w)
  press("ctrl+alt", "h")
  frameIs("t121 runs", w, { x = 0, y = 25, w = 960, h = 1055 })
  local settings = world.settings
  install(laptop())
  world.settings = settings
  anchors.start()
  check("t121 survives", hotkey("ctrl+alt", "h") ~= nil)
  openSettings()
  send({ type = "reset", action = "left-half" })
  check("t121 reset", hotkey("ctrl+alt", "left") ~= nil and hotkey("ctrl+alt", "h") == nil)
  check("t121 default again", modelRow("left-half").source == "default")
  send({ type = "unbind", action = "left-half" })
  check("t121 cleared", hotkey("ctrl+alt", "left") == nil and modelRow("left-half").key == "")
end

-- Test 122: A bare key, an unknown key and an unknown action are refused with a notice.
tests[#tests + 1] = function()
  install(laptop())
  anchors.start()
  openSettings()
  send({ type = "record", on = true })
  send({ type = "bind", action = "left-half", code = "KeyH" })
  check("t122 bare", world.model.notice == "Add Control, Option or Command to that key.")
  check("t122 shortcuts back", enabledCount() == 22)
  send({ type = "bind", action = "left-half", code = "IntlYen", ctrl = true })
  check("t122 unknown key", world.model.notice == "That key cannot be bound.")
  send({ type = "bind", action = "sideways", code = "KeyH", ctrl = true })
  check("t122 unknown action", world.model.notice == "Unknown action sideways.")
  send({ type = "unbind", action = "sideways" })
  check("t122 nothing saved", world.settings["moorings.shortcuts"] == nil)
  send({ type = "dance" })
  check("t122 unknown message", said("the settings window sent an unknown message") == 1)
  send("junk")
  check("t122 junk", said("the settings window sent an unknown message") == 1)
end

-- Test 123: A key saved in the window beats the config, and the source says which applies.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.shortcuts = {
    ["left-half"] = { mods = { "ctrl", "alt" }, key = "g" },
    center = { mods = { "ctrl", "alt" }, key = "x" },
  }
  anchors.start()
  openSettings()
  check("t123 config", modelRow("center").source == "config")
  send({ type = "bind", action = "left-half", code = "KeyH", ctrl = true, alt = true })
  check("t123 saved wins", modelRow("left-half").key == "⌃⌥H")
  check("t123 default freed", modelRow("last-third").key == "⌃⌥G")
  send({ type = "reset", action = "left-half" })
  check("t123 config back", modelRow("left-half").key == "⌃⌥G" and modelRow("last-third").key == "")
end

-- Test 124: Sizes are added, edited, renamed, refused when invalid, deleted, and can lay over
-- a config size.
tests[#tests + 1] = function()
  install(laptop())
  anchors.config.sizes = { { title = "Video", width = 1280, height = 720 } }
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  openSettings()
  check("t124 config row", #world.model.sizes == 1 and world.model.sizes[1].saved == false)
  send({ type = "saveSize", size = { title = "Reading", x = "0.25", w = "0.5" } })
  check("t124 notice", world.model.notice == "Reading is saved.")
  check("t124 rows", #world.model.sizes == 2 and world.model.sizes[1].title == "Reading")
  check("t124 bindable row", modelRow("size:Reading") ~= nil)
  focus(w)
  action("size:Reading").fn()
  frameIs("t124 runs", w, { x = 480, y = 25, w = 960, h = 1055 })
  send({ type = "saveSize", old = "Reading", size = { title = "Read", x = "0.25", w = "0.25" } })
  check("t124 renamed", #anchors.savedSizes() == 1 and anchors.savedSizes()[1].title == "Read")
  send({ type = "saveSize", size = { title = "Broken", w = "2" } })
  check("t124 refused", world.model.notice:find("^Not saved: size Broken needs") ~= nil, world.model.notice)
  check("t124 not stored", #anchors.savedSizes() == 1)
  send({ type = "saveSize", size = { title = "Video", width = "800", height = "600" } })
  check("t124 over config", #anchors.sizeList() == 2 and anchors.sizeList()[1].width == 800)
  send({ type = "bind", action = "size:Read", code = "KeyY", ctrl = true, alt = true })
  check("t124 size key", hotkey("ctrl+alt", "y") ~= nil and #world.model.problems == 0,
    table.concat(world.model.problems, "; "))
  send({ type = "saveSize", old = "Read", size = { title = "Skim", x = "0.25", w = "0.25" } })
  check("t124 key follows rename", modelRow("size:Skim").key == "⌃⌥Y" and #world.model.problems == 0,
    table.concat(world.model.problems, "; "))
  send({ type = "deleteSize", title = "Skim" })
  check("t124 deleted", #anchors.savedSizes() == 1 and anchors.savedSizes()[1].title == "Video")
  check("t124 key dropped", hotkey("ctrl+alt", "y") == nil and #world.model.problems == 0
    and anchors.savedShortcuts()["size:Skim"] == nil)
end

-- Test 125: The gap, keymap and snapping are set from the window, and a bad gap is refused.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 500, y = 300, w = 800, h = 500 })
  anchors.start()
  openSettings()
  send({ type = "gap", value = "10" })
  check("t125 gap", anchors.gapPx() == 10 and world.model.gap == 10)
  focus(w)
  press("ctrl+alt", "left")
  frameIs("t125 gap used", w, { x = 10, y = 35, w = 945, h = 1035 })
  for _, bad in ipairs({ "abc", "-1", "2.5", "101" }) do
    send({ type = "gap", value = bad })
    check("t125 refused " .. bad, world.model.notice == "The gap must be a whole number from 0 to 100."
      and anchors.gapPx() == 10)
  end
  send({ type = "keymap", name = "spectacle" })
  check("t125 keymap", world.model.keymap == "spectacle" and hotkey("alt+cmd", "f") ~= nil)
  send({ type = "keymap", name = "vim" })
  check("t125 bad keymap", world.model.keymap == "spectacle")
  send({ type = "snap", on = false })
  check("t125 snap off", anchors.snapOn() == false and item("Snap by dragging").checked == false)
  send({ type = "snap", on = true })
  check("t125 snap on", anchors.snapOn() == true)
end

-- Test 126: Workspaces are saved, tied, recalled and deleted from the window.
tests[#tests + 1] = function()
  install(laptop())
  local w = addWin("Safari", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  openSettings()
  send({ type = "saveWorkspace", name = "  " })
  check("t126 blank", world.model.notice == "Name the workspace first." and #world.model.workspaces == 0)
  send({ type = "saveWorkspace", name = " Night " })
  check("t126 saved", world.model.notice == "Night is saved." and world.model.workspaces[1].name == "Night"
    and world.model.workspaces[1].tied == false)
  send({ type = "tie", name = "Night" })
  check("t126 tied", world.model.workspaces[1].tied == true)
  w.f = { x = 500, y = 300, w = 600, h = 400 }
  send({ type = "recall", name = "Night" })
  frameIs("t126 recalled", w, { x = 100, y = 100, w = 900, h = 700 })
  send({ type = "deleteWorkspace", name = "Night" })
  check("t126 deleted", #world.model.workspaces == 0)
end

-- Test 127: A missing page is reported and no window opens.
tests[#tests + 1] = function()
  install(laptop())
  anchors.start()
  anchors.path = function(file) return "/nonexistent/" .. file end
  click("Settings window…")
  check("t127 said", said("settings.html is missing from the moorings folder") == 1)
  check("t127 no window", world.view == nil)
end

-- Test 128: A pinned window that goes native fullscreen leaves it and lands in its slot.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  frameIs("t128 pinned", term, { x = 2816, y = 25, w = 2304, h = 1415 })
  check("t128 checked", item("Fullscreen keeps anchored apps in their slots").checked == true)
  term.full = true
  term.f = { x = 0, y = 0, w = 5120, h = 1440 }
  world.onEvent()
  check("t128 left fullscreen", term.full == false)
  world.poll()
  frameIs("t128 back in slot", term, { x = 2816, y = 25, w = 2304, h = 1415 })
end

-- Test 129: Unticking the pin setting leaves a pinned window in native fullscreen.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  click("Fullscreen keeps anchored apps in their slots")
  check("t129 unchecked", item("Fullscreen keeps anchored apps in their slots").checked == false)
  term.full = true
  world.poll()
  world.clock = world.clock + 10
  world.poll()
  check("t129 still fullscreen", term.full == true)
end

-- Test 130: The pin and channel fullscreen settings work independently.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  local free = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  anchors.start()
  click("Fullscreen fills the channel")
  term.full, free.full = true, true
  world.poll()
  check("t130 pin redirected", term.full == false)
  check("t130 free kept", free.full == true)
  term.full, free.full = false, false
  click("Fullscreen fills the channel")
  click("Fullscreen keeps anchored apps in their slots")
  world.clock = world.clock + 10
  term.full, free.full = true, true
  world.poll()
  check("t130 pin kept", term.full == true)
  check("t130 free redirected", free.full == false)
end

-- Test 131: A pinned app's other window in native fullscreen is left alone.
tests[#tests + 1] = function()
  install(ultrawide())
  addWin("Slack", { x = 1000, y = 100, w = 900, h = 700 })
  local huddle = addWin("Slack", { x = 1200, y = 200, w = 400, h = 300 })
  huddle.secondary = true
  anchors.start()
  huddle.full = true
  world.poll()
  check("t131 huddle fullscreen", huddle.full == true)
  check("t131 huddle unmoved", huddle.moves == 0)
end

-- Test 132: A pinned window still animating out of fullscreen is told to leave once.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  local calls = 0
  term.setFullScreen = function() calls = calls + 1 end
  term.full = true
  world.poll()
  world.poll()
  check("t132 once", calls == 1, calls)
  world.clock = world.clock + 10
  world.poll()
  check("t132 retried later", calls == 2, calls)
end

-- Test 133: A pinned window that lands in its slot and goes fullscreen again is redirected again.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  term.full = true
  world.poll()
  world.poll()
  check("t133 first back", term.full == false)
  term.full = true
  world.poll()
  check("t133 second back", term.full == false)
end

-- Test 134: The pin fullscreen setting survives reload.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  click("Fullscreen keeps anchored apps in their slots")
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  anchors.start()
  check("t134 survives reload", item("Fullscreen keeps anchored apps in their slots").checked == false)
end

-- Test 135: Icons sit in folders, every built-in is unique, and the default stays first.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  check("t135 folders", titles(folder("Settings")):find("Icon", 1, true) ~= nil)
  local icons = item("Icon").menu
  check("t135 groups", titles(icons) == "moorings mark,Boats,Sea life,Tools,Hearts and shapes,-,Custom…,Surprise me,"
    .. "Default icon,Undo icon change,-,Open icons folder", titles(icons))
  check("t135 count", #anchors.icons >= 40, #anchors.icons)
  local names, glyphs = {}, {}
  for _, icon in ipairs(anchors.icons) do
    check("t135 unique name " .. icon.name, not names[icon.name])
    check("t135 unique glyph " .. icon.name, not glyphs[icon.glyph])
    names[icon.name], glyphs[icon.glyph] = true, true
  end
  check("t135 default", anchors.icons[1].name == "Sailboat" and markShown())
  click("🐳  Whale")
  check("t135 nested pick", world.bar.title == "🐳")
end

-- Test 136: validIcon accepts 1 to 5 code points after trimming and refuses the rest.
tests[#tests + 1] = function()
  install(ultrawide())
  local cases = {
    { "", nil }, { "   ", nil }, { "A", "A" }, { "  AB  ", "AB" }, { "🐙", "🐙" },
    { "abcde", "abcde" }, { "abcdef", nil }, { "🛥️🛥️", "🛥️🛥️" }, { "a b c", "a b c" },
    { "\xff", nil }, { nil, nil }, { 7, nil },
  }
  for i, c in ipairs(cases) do
    local got, problem = anchors.validIcon(c[1])
    check("t136 case " .. i, got == c[2], tostring(got))
    check("t136 reason " .. i, (got == nil) == (problem ~= nil))
  end
end

-- Test 137: A custom icon sets the title, shows checked, and survives reload.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  world.prompt, world.hsFocused = { "Set", "  DCA " }, nil
  click("Custom…")
  check("t137 prompt in front", world.focusedAtPrompt == true)
  check("t137 title", world.bar.title == "DCA", world.bar.title)
  check("t137 prompt text", world.promptArgs[1] == "Custom icon")
  check("t137 checked", item("Custom…  DCA").checked == true)
  check("t137 builtin unchecked", item("⛵  Sailboat").checked == false)
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  anchors.start()
  check("t137 survives reload", world.bar.title == "DCA")
  world.prompt = { "Set", "" }
  world.alerted = nil
  click("Custom…  DCA")
  check("t137 prefilled", world.promptArgs[3] == "DCA", tostring(world.promptArgs[3]))
end

-- Test 138: Bad or cancelled input leaves the icon alone and bad input alerts.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  world.prompt = { "Set", "toolong" }
  click("Custom…")
  check("t138 refused", markShown())
  check("t138 alert", world.alerted == "Enter 1 to 5 characters.", tostring(world.alerted))
  check("t138 not saved", world.settings["moorings.customIcon"] == nil)
  world.alerted = nil
  world.prompt = { "Cancel", "OK" }
  click("Custom…")
  check("t138 cancel", markShown() and world.alerted == nil)
  check("t138 cancel not saved", world.settings["moorings.customIcon"] == nil)
end

-- Test 139: Picking a built-in icon replaces a custom one, and a bad saved custom value is ignored.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  world.prompt = { "Set", "DCA" }
  click("Custom…")
  click("🐙  Octopus")
  check("t139 title", world.bar.title == "🐙")
  check("t139 custom cleared", world.settings["moorings.customIcon"] == nil)
  check("t139 checked", item("🐙  Octopus").checked == true)
  world.settings["moorings.customIcon"] = "far too long"
  check("t139 bad saved ignored", item("🐙  Octopus").checked == true)
  world.prompt = { "Set", "⛵" }
  click("Custom…")
  check("t139 custom twin", item("Custom…  ⛵").checked == true and item("⛵  Sailboat").checked == false)
  world.settings["moorings.customIcon"] = nil
  world.settings["moorings.icon"] = "Gone"
  world.settings["moorings.customIcon"] = nil
  check("t139 unknown name falls back", item("moorings mark").checked == true)
end

-- Test 140: Config icons show under Yours, bad entries are logged and skipped, and a pick survives reload.
tests[#tests + 1] = function()
  install(ultrawide())
  world.images["/img/wave.png"] = true
  anchors.config.icons = {
    { name = "Mine", glyph = " AB " },
    { name = "Wavy", image = "/img/wave.png" },
    { glyph = "X" },
    { name = "Crab", glyph = "X" },
    { name = "Long", glyph = "toolong" },
    { name = "image:sneaky", glyph = "X" },
    { name = "Both", glyph = "X", image = "/img/wave.png" },
    { name = "Mine", glyph = "Z" },
    { name = "Empty", image = "" },
    "text",
  }
  anchors.start()
  check("t140 yours", titles(item("Yours").menu) == "AB  Mine,Wavy", titles(item("Yours").menu))
  for _, n in ipairs({ 3, 4, 5, 6, 7, 8, 9, 10 }) do
    local want = "moorings: icons entry " .. n .. " is skipped: it needs a unique name and a glyph or an image"
    local found = false
    for _, line in ipairs(world.printed) do found = found or line == want end
    check("t140 logged " .. n, found)
  end
  click("AB  Mine")
  check("t140 glyph", world.bar.title == "AB" and world.bar.icon == nil)
  check("t140 checked", item("AB  Mine").checked == true)
  click("Wavy")
  check("t140 image", world.bar.icon and world.bar.icon.path == "/img/wave.png")
  check("t140 template", world.bar.iconTemplate == true and world.bar.icon.isTemplate == true)
  check("t140 size", world.bar.icon.size.w == 18 and world.bar.icon.size.h == 18)
  check("t140 no title", world.bar.title == nil)
  local settings = world.settings
  local cfg = anchors.config.icons
  install(ultrawide())
  world.settings, world.images["/img/wave.png"] = settings, true
  anchors.config.icons = cfg
  anchors.start()
  check("t140 survives reload", world.bar.icon and world.bar.icon.path == "/img/wave.png")
  click("🐙  Octopus")
  check("t140 back to glyph", world.bar.title == "🐙" and world.bar.icon == nil)
  world.images["/img/wave.png"] = nil
  world.settings["moorings.icon"] = "Wavy"
  anchors.start()
  check("t140 unloadable falls back", markShown())
  check("t140 unloadable unchecked", item("Wavy").checked ~= true)
  check("t140 default checked", item("moorings mark").checked == true)
end

-- Test 141: Image files in the icon folder are listed, sorted, filtered, and loaded as template images.
tests[#tests + 1] = function()
  install(ultrawide())
  local dir = anchors.iconDir()
  check("t141 dir", dir == "/tmp/hammerspoon/moorings/icons", dir)
  anchors.start()
  check("t141 no folder no yours", item("Yours") == nil)
  for _, line in ipairs(world.printed) do
    check("t141 quiet without folder", not line:find("open", 1, true), line)
  end
  world.alerted = nil
  click("Open icons folder")
  check("t141 says how", world.alerted == "Create " .. dir .. " and add PNG or SVG files, then reopen the menu.",
    tostring(world.alerted))
  check("t141 not created", world.dirs[dir] == nil and world.executed == nil)
  world.dirs[dir] = { "b.PNG", "A.svg", ".hidden.png", "notes.txt", "noext", "c.jpeg" }
  for _, f in ipairs({ "b.PNG", "A.svg", "c.jpeg" }) do world.images[dir .. "/" .. f] = true end
  check("t141 listed", titles(item("Yours").menu) == "A,b,c", titles(item("Yours").menu))
  click("Open icons folder")
  check("t141 opens", world.executed == "open '" .. dir .. "'", tostring(world.executed))
  click("b")
  check("t141 loaded", world.bar.icon and world.bar.icon.path == dir .. "/b.PNG" and world.bar.title == nil)
  check("t141 checked", item("b").checked == true and item("A").checked == false)
  check("t141 saved name", world.settings["moorings.icon"] == "image:b.PNG")
end

-- Test 142: Surprise me never picks the current icon, and picks from every built-in when the
-- mark or text is in effect.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  local asked
  anchors.random = function(n) asked = n return 1 end
  click("Surprise me")
  check("t142 mark pool", asked == #anchors.icons and world.bar.title == anchors.icons[1].glyph,
    tostring(asked))
  click("Surprise me")
  check("t142 pool", asked == #anchors.icons - 1, tostring(asked))
  check("t142 first other", world.bar.title == anchors.icons[2].glyph)
  anchors.random = function(n) asked = n return n end
  click("Surprise me")
  check("t142 last", world.bar.title == anchors.icons[#anchors.icons].glyph)
  check("t142 pool again", asked == #anchors.icons - 1)
  anchors.random = function(n) asked = n return 1 end
  world.settings["moorings.icon"] = "Sailboat"
  click("Surprise me")
  check("t142 skips current", world.bar.title == anchors.icons[2].glyph)
  world.prompt = { "Set", "DCA" }
  click("Custom…")
  click("Surprise me")
  check("t142 from custom", world.bar.title == anchors.icons[1].glyph and asked == #anchors.icons, tostring(asked))
  check("t142 custom cleared", world.settings["moorings.customIcon"] == nil)
end

-- Test 143: Default icon resets, and Undo icon change toggles between the last two choices.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  check("t143 undo off", item("Undo icon change").disabled == true)
  check("t143 undo refused", anchors.undoIcon() == nil and select(2, anchors.undoIcon()) == "There is no icon change to undo.")
  click("🐙  Octopus")
  check("t143 undo on", item("Undo icon change").disabled == false)
  click("Undo icon change")
  check("t143 undone", markShown() and world.settings["moorings.icon"] == nil)
  click("Undo icon change")
  check("t143 redone", world.bar.title == "🐙" and world.settings["moorings.icon"] == "Octopus")
  world.prompt = { "Set", "DCA" }
  click("Custom…")
  check("t143 custom", world.bar.title == "DCA")
  click("Default icon")
  check("t143 default", markShown() and world.settings["moorings.icon"] == nil
    and world.settings["moorings.customIcon"] == nil)
  click("Undo icon change")
  check("t143 custom back", world.bar.title == "DCA" and world.settings["moorings.customIcon"] == "DCA")
end

-- Test 144: Picking an unknown icon changes nothing and says why.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  local ok, why = anchors.pickIcon("Nope")
  check("t144 refused", ok == nil and why == "That icon is not available.")
  check("t144 unchanged", markShown() and world.settings["moorings.icon"] == nil)
  check("t144 no undo", item("Undo icon change").disabled == true)
end

-- Test 145: The settings window sends the icon model and runs every icon message.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  openSettings()
  local icons = world.model.icons
  check("t145 groups", #icons.groups == 4 and icons.groups[1].title == "Boats")
  check("t145 default checked", icons.mark.checked and not icons.groups[1].icons[1].checked)
  check("t145 undo off", icons.canUndo == false and icons.usingCustom == false)
  send({ type = "iconUndo" })
  check("t145 undo refused", world.model.notice == "There is no icon change to undo." and markShown())
  send({ type = "iconPick", name = "Octopus" })
  check("t145 picked", world.bar.title == "🐙" and world.model.icons.canUndo == true)
  check("t145 no notice", world.model.notice == "")
  send({ type = "iconPick", name = "Nope" })
  check("t145 unknown", world.model.notice == "That icon is not available." and world.bar.title == "🐙")
  send({ type = "iconCustom", text = "toolong" })
  check("t145 bad text", world.model.notice == "Enter 1 to 5 characters." and world.bar.title == "🐙")
  send({ type = "iconCustom", text = "DCA" })
  check("t145 custom", world.bar.title == "DCA" and world.model.icons.custom == "DCA"
    and world.model.icons.usingCustom == true and world.model.notice == "")
  send({ type = "iconUndo" })
  check("t145 undo", world.bar.title == "🐙")
  send({ type = "iconDefault" })
  check("t145 default", markShown())
  anchors.random = function() return 1 end
  send({ type = "iconSurprise" })
  check("t145 surprise", world.bar.title == anchors.icons[1].glyph)
  send({ type = "iconFolder" })
  check("t145 folder", world.alerted ~= nil and world.alerted:find("Create ", 1, true) == 1)
end

-- Test 146: The settings page has an element for every icon control its script uses.
tests[#tests + 1] = function()
  local file = assert(io.open("settings.html", "r"))
  local html = file:read("a")
  file:close()
  for _, id in ipairs({ "icons", "iconGroups", "iconText", "saveIcon", "iconSurprise", "iconDefault",
    "iconUndo", "iconFolder" }) do
    check("t146 markup " .. id, html:find('id="' .. id .. '"', 1, true) ~= nil)
    check("t146 script " .. id, id == "icons" or html:find('getElementById("' .. id .. '")', 1, true) ~= nil)
  end
  check("t146 tab", html:find('data-tab="icons"', 1, true) ~= nil)
end

-- dragTaps counts the running and stopped left mouse taps, which belong to snap.
local function dragTaps()
  local running, stopped = 0, 0
  for _, tap in ipairs(world.taps) do
    if tap.types[1] == 1 then
      if tap.running then running = running + 1 else stopped = stopped + 1 end
    end
  end
  return running, stopped
end

-- Test 147: The moorings mark ships with moorings, is the default, loads as a template
-- image, and gives way to the sailboat, logged once, only when it does not load.
tests[#tests + 1] = function()
  install(ultrawide())
  world.images[markPath] = nil
  anchors.start()
  check("t147 missing falls back", world.bar.title == "⛵" and world.bar.icon == nil)
  check("t147 missing default checked", item("⛵  Sailboat").checked == true
    and item("moorings mark").checked == false)
  world.clock = world.clock + 3600
  item("Icon")
  check("t147 logged once", said("mark.svg did not load: using Sailboat") == 1,
    "count " .. said("mark.svg did not load: using Sailboat"))
  install(ultrawide())
  anchors.start()
  check("t147 default", markShown() and world.bar.icon.isTemplate == true
    and world.bar.icon.size.w == 18)
  check("t147 default checked", item("moorings mark").checked == true
    and item("⛵  Sailboat").checked == false)
  check("t147 nothing saved", world.settings["moorings.icon"] == nil)
  click("⛵  Sailboat")
  check("t147 sailboat pick", world.bar.title == "⛵" and world.bar.icon == nil)
  click("moorings mark")
  check("t147 image", markShown())
  check("t147 checked", item("moorings mark").checked == true and item("⛵  Sailboat").checked == false)
  check("t147 saved", world.settings["moorings.icon"] == "moorings mark")
  local f = io.open("mark.svg", "r")
  check("t147 file in repo", f ~= nil)
  if f then f:close() end
  anchors.path = function(file) return "./" .. file end
  world.images["./mark.svg"] = true
  click("Settings window…")
  world.webMsg({ body = { type = "ready" } })
  check("t147 model", world.model.icons.mark.checked == true and world.model.icons.mark.image == true)
end

-- Test 148: Choosing the icon already in effect keeps the undo point, the notice stays
-- until handled, a config icon cannot take the mark's name, and the page keeps a draft.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.icons = { { name = "moorings mark", glyph = "X" } }
  anchors.start()
  check("t148 mark name refused", item("Yours") == nil)
  click("🐙  Octopus")
  click("🐙  Octopus")
  click("Undo icon change")
  check("t148 undo after repeat", markShown(), tostring(world.bar.title))
  click("Default icon")
  check("t148 default no-op keeps undo", item("Undo icon change").disabled == false)
  click("Undo icon change")
  check("t148 undo to octopus", world.bar.title == "🐙")
  install(ultrawide())
  world.trusted = false
  anchors.start()
  check("t148 notice stays", world.notices[1].attrs.withdrawAfter == 0)
  local file = assert(io.open("settings.html", "r"))
  local html = file:read("a")
  file:close()
  check("t148 draft kept", html:find("if (saved !== lastIconText)", 1, true) ~= nil)
end

-- Test 149: Missing Accessibility shows the warning glyph, one notification and a menu item to grant it.
tests[#tests + 1] = function()
  install(ultrawide())
  world.trusted = false
  anchors.start()
  check("t149 glyph", world.bar.title == "⚠️" and world.bar.icon == nil, tostring(world.bar.title))
  check("t149 one notice", #world.notices == 1 and world.notices[1].sent == true)
  check("t149 notice text", world.notices[1].attrs.title == "moorings needs Accessibility"
    and world.notices[1].attrs.hasActionButton == true)
  local items = world.bar.menu()
  check("t149 first item", items[1].title == "⚠️ Grant Accessibility access" and items[2].title == "-")
  click("⚠️ Grant Accessibility access")
  local pane = "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
  check("t149 opens pane", world.executed == pane, tostring(world.executed))
  world.executed = nil
  world.notices[1].fn()
  check("t149 notice opens pane", world.executed == pane)
  local calls = world.bar.titleCalls
  for _ = 1, 5 do world.poll() end
  check("t149 no redraw per tick", world.bar.titleCalls == calls, world.bar.titleCalls .. " vs " .. calls)
  check("t149 still one notice", #world.notices == 1)
  check("t149 still glyph", world.bar.title == "⚠️")
end

-- Test 150: Granting Accessibility clears the warning once and binds shortcuts and the drag tap again.
tests[#tests + 1] = function()
  install(ultrawide())
  world.trusted = false
  anchors.start()
  local before = #world.hotkeys
  local oldKey = world.hotkeys[1]
  check("t150 one drag tap", select(1, dragTaps()) == 1)
  world.trusted = true
  world.poll()
  check("t150 icon back", markShown())
  check("t150 withdrawn", world.notices[1].withdrawn == true)
  check("t150 alert", world.alerted == "moorings: Accessibility granted", tostring(world.alerted))
  check("t150 rebound", #world.hotkeys == 2 * before and oldKey.deleted == true and world.hotkeys[before + 1].enabled)
  local running, stopped = dragTaps()
  check("t150 drag tap replaced", running == 1 and stopped == 1, running .. " " .. stopped)
  check("t150 no grant item", world.bar.menu()[1].title ~= "⚠️ Grant Accessibility access")
  world.alerted = nil
  world.poll()
  check("t150 once", world.alerted == nil and #world.hotkeys == 2 * before)
end

-- Test 151: A later loss shows the glyph again without a second notification, and the
-- warning wins over an icon picked meanwhile.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  check("t151 trusted start quiet", #world.notices == 0 and markShown())
  check("t151 no grant item", world.bar.menu()[1].title ~= "⚠️ Grant Accessibility access")
  world.trusted = false
  world.poll()
  check("t151 lost", world.bar.title == "⚠️" and #world.notices == 1)
  click("🐙  Octopus")
  check("t151 warning wins", world.bar.title == "⚠️")
  world.trusted = true
  world.poll()
  check("t151 picked shows", world.bar.title == "🐙")
  world.trusted = false
  world.poll()
  check("t151 no second notice", world.bar.title == "⚠️" and #world.notices == 1)
end

-- Test 152: The grant is picked up while the layout is frozen.
tests[#tests + 1] = function()
  install(ultrawide())
  world.trusted = false
  anchors.start()
  click("⚓ Raise anchor (let windows drift)")
  world.trusted = true
  world.poll()
  check("t152 picked up", markShown() and world.notices[1].withdrawn == true)
end

-- stackedLeft pins Notes in the left top row and Slack below it, and returns both windows.
local function stackedLeft()
  anchors.config.pins = {
    { bundle = "test.Notes", side = "left", row = "top" },
    { bundle = "com.tinyspeck.slackmacgap", side = "left", row = "bottom" },
    { bundle = "com.googlecode.iterm2", side = "right" },
  }
  local notes = addWin("Notes", { x = 1000, y = 100, w = 400, h = 400 })
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  return notes, slack
end

-- heightPreset clicks the preset top of the side folder titled name.
local function heightPreset(name, top)
  local title = string.format("Top %d%%, bottom %d%%", top, 100 - top)
  local side = item(name, folder("Heights"))
  local it = side and item(title, side.menu)
  check("heights has " .. name .. " " .. title, it ~= nil)
  if it then it.fn({}, it) end
end

-- checkedHeights lists the checked preset of each side folder.
local function checkedHeights()
  local out = {}
  for _, name in ipairs({ "Left side", "Right side" }) do
    for _, it in ipairs(item(name, folder("Heights")).menu) do
      if it.checked then out[#out + 1] = name .. " " .. it.title end
    end
  end
  return table.concat(out, ",")
end

-- Test 153: With nothing chosen the rows split evenly and the Heights folder says so.
tests[#tests + 1] = function()
  install(ultrawide())
  local notes, slack = stackedLeft()
  anchors.start()
  frameIs("t153 notes", notes, leftTop)
  frameIs("t153 slack", slack, leftBottom)
  check("t153 labels", titles(folder("Heights")) == "Left top 50%, bottom 50%,"
    .. "Right top 50%, bottom 50%,Left top taller,Left top shorter,Right top taller,"
    .. "Right top shorter,Left side,Right side", titles(folder("Heights")))
  check("t153 label off", item("Left top 50%, bottom 50%").disabled == true)
  check("t153 checked", checkedHeights()
    == "Left side Top 50%, bottom 50%,Right side Top 50%, bottom 50%", checkedHeights())
end

-- Test 154: A preset sets one side's top row and leaves the other side alone.
tests[#tests + 1] = function()
  install(ultrawide())
  local notes, slack = stackedLeft()
  anchors.start()
  heightPreset("Left side", 10)
  frameIs("t154 notes short", notes, { x = 0, y = 25, w = 512, h = 141 })
  frameIs("t154 slack tall", slack, { x = 0, y = 166, w = 512, h = 1274 })
  local l, r = anchors.heights()
  check("t154 heights", l == 10 and r == 50, l .. " " .. r)
  check("t154 label", item("Left top 10%, bottom 90%") ~= nil)
  check("t154 checked", checkedHeights()
    == "Left side Top 10%, bottom 90%,Right side Top 50%, bottom 50%", checkedHeights())
  for _, top in ipairs(anchors.heightPresets) do
    heightPreset("Left side", top)
    local h = math.floor(1415 * top / 100)
    frameIs("t154 notes " .. top, notes, { x = 0, y = 25, w = 512, h = h })
    frameIs("t154 slack " .. top, slack, { x = 0, y = 25 + h, w = 512, h = 1415 - h })
  end
end

-- Test 155: The steppers move a top row by five points and stop with either row at 10.
tests[#tests + 1] = function()
  install(ultrawide())
  local notes, slack = stackedLeft()
  anchors.start()
  click("Left top taller")
  frameIs("t155 taller", notes, { x = 0, y = 25, w = 512, h = 778 })
  frameIs("t155 below", slack, { x = 0, y = 803, w = 512, h = 637 })
  check("t155 right kept", select(2, anchors.heights()) == 50)
  check("t155 no preset", checkedHeights() == "Right side Top 50%, bottom 50%", checkedHeights())
  click("Left top shorter")
  frameIs("t155 back", notes, leftTop)
  anchors.setHeights(90, 10)
  check("t155 taller off", item("Left top taller").disabled == true)
  check("t155 shorter on", item("Left top shorter").disabled == false)
  check("t155 right shorter off", item("Right top shorter").disabled == true)
  check("t155 refused", anchors.stepTop("left", 5) == false
    and anchors.stepTop("right", -5) == false)
  local l, r = anchors.heights()
  check("t155 unchanged", l == 90 and r == 10, l .. " " .. r)
  click("Right top taller")
  check("t155 right stepped", select(2, anchors.heights()) == 15)
end

-- Test 156: Config heights apply until a choice is saved, and a bad one falls back to 50
-- without repeating its log line on every poll.
tests[#tests + 1] = function()
  install(ultrawide())
  local notes = stackedLeft()
  anchors.config.leftTopPct = 25
  anchors.config.rightTopPct = 95
  anchors.start()
  frameIs("t156 config", notes, { x = 0, y = 25, w = 512, h = 353 })
  world.poll()
  world.poll()
  check("t156 bad right", select(2, anchors.heights()) == 50)
  check("t156 one log", said("rightTopPct must be a number from 10 to 90") == 1,
    tostring(said("rightTopPct must be")))
  check("t156 left quiet", said("leftTopPct") == 0)
  heightPreset("Left side", 75)
  frameIs("t156 choice wins", notes, { x = 0, y = 25, w = 512, h = 1061 })
  anchors.config.leftTopPct = "tall"
  hs.settings.clear("moorings.heights")
  check("t156 junk config", select(1, anchors.heights()) == 50)
end

-- Test 157: A partial or junk saved height is read side by side against the config.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.rightTopPct = 30
  world.settings["moorings.heights"] = { left = 20 }
  local l, r = anchors.heights()
  check("t157 partial", l == 20 and r == 30, l .. " " .. r)
  world.settings["moorings.heights"] = { left = 5, right = "x" }
  l, r = anchors.heights()
  check("t157 bad values", l == 50 and r == 30, l .. " " .. r)
  world.settings["moorings.heights"] = "junk"
  l, r = anchors.heights()
  check("t157 junk", l == 50 and r == 30, l .. " " .. r)
  anchors.start()
  check("t157 menu builds", item("Left top 50%, bottom 50%") ~= nil
    and item("Right top 30%, bottom 70%") ~= nil)
end

-- Test 158: Expand on focus widens a stacked pin and keeps its chosen height.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.pins = {
    { bundle = "com.tinyspeck.slackmacgap", side = "left", row = "top", expandPct = 30 },
    { bundle = "test.Notes", side = "left", row = "bottom" },
  }
  local slack = addWin("Slack", leftTop)
  local notes = addWin("Notes", leftBottom)
  world.settings["moorings.heights"] = { left = 25, right = 50 }
  anchors.start()
  focus(slack)
  world.onEvent()
  frameIs("t158 slack expanded", slack, { x = 0, y = 25, w = 1536, h = 353 })
  frameIs("t158 notes kept", notes, { x = 0, y = 378, w = 512, h = 1062 })
end

-- Test 159: A side with one pin fills the full height whatever its top row height is.
tests[#tests + 1] = function()
  install(ultrawide())
  world.settings["moorings.heights"] = { left = 10, right = 90 }
  local slack = addWin("Slack", { x = 2000, y = 100, w = 900, h = 700 })
  local term = addWin("iTerm2", { x = 100, y = 100, w = 900, h = 700 })
  anchors.start()
  frameIs("t159 slack full", slack, leftFull)
  frameIs("t159 iterm full", term, rightFull)
  frameIs("t159 slot frame", { f = anchors.slotFrame(world.screens[1], "left-bottom") },
    { x = 0, y = 166, w = 512, h = 1274 })
end

-- Test 160: A workspace puts back its heights, and one saved without heights or with bad
-- heights keeps the heights in effect.
tests[#tests + 1] = function()
  install(ultrawide())
  local notes = stackedLeft()
  anchors.start()
  heightPreset("Left side", 25)
  heightPreset("Right side", 67)
  saveAs("Calendar")
  heightPreset("Left side", 90)
  anchors.recallWorkspace("Calendar")
  local l, r = anchors.heights()
  check("t160 recalled", l == 25 and r == 67, l .. " " .. r)
  frameIs("t160 notes", notes, { x = 0, y = 25, w = 512, h = 353 })
  local list = world.settings["moorings.workspaces"]
  list.Old = { left = 10, right = 45, windows = {} }
  list.Bad = { left = 10, right = 45, heights = { left = 5, right = 50 }, windows = {} }
  world.settings["moorings.workspaces"] = list
  anchors.recallWorkspace("Old")
  l, r = anchors.heights()
  check("t160 old kept", l == 25 and r == 67, l .. " " .. r)
  anchors.recallWorkspace("Bad")
  l, r = anchors.heights()
  check("t160 bad kept", l == 25 and r == 67, l .. " " .. r)
end

-- Test 161: A chosen height survives reload.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  heightPreset("Left side", 10)
  local settings = world.settings
  install(ultrawide())
  world.settings = settings
  local notes = stackedLeft()
  anchors.start()
  frameIs("t161 kept", notes, { x = 0, y = 25, w = 512, h = 141 })
end

-- Test 162: Choose app browses Applications, locks the app picked and launches it, and the
-- slot list shows it checked while it is not running.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  world.chosenFile = { ["1"] = "/Applications/Calendar.app" }
  pick("Left bottom: Empty", "Choose app…")
  check("t162 focused", world.hsFocused == true)
  check("t162 browser", world.chooseArgs[2] == "/Applications" and world.chooseArgs[3] == true
    and world.chooseArgs[4] == false and world.chooseArgs[6][1] == "app")
  check("t162 assigned", anchors.assignments()["left-bottom"] == "test.Calendar")
  check("t162 opened", table.concat(world.opened, ",") == "/usr/bin/open -b test.Calendar",
    table.concat(world.opened, ","))
  frameIs("t162 slack top", slack, leftTop)
  local choices = item("Left bottom: Calendar").menu
  check("t162 listed", titles(choices) == "Empty,Calendar,Slack,-,Choose app…", titles(choices))
  check("t162 checked", item("Calendar", choices).checked == true)
  world.chosenFile = { ["1"] = "/Applications/Calendar.app" }
  pick("Left top: Slack", "Choose app…")
  check("t162 moved", anchors.assignments()["left-top"] == "test.Calendar"
    and anchors.assignments()["left-bottom"] == "")
end

-- Test 163: Canceling the browser, a path that is not an app and an ignored app change nothing.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.config.ignoreBundles = { "test.Zoom" }
  anchors.start()
  local before = anchors.assignments()["left-bottom"]
  world.chosenFile = nil
  pick("Left bottom: Empty", "Choose app…")
  world.chosenFile = {}
  pick("Left bottom: Empty", "Choose app…")
  check("t163 cancel", anchors.assignments()["left-bottom"] == before and world.alerted == nil)
  world.chosenFile = { ["1"] = "/tmp" }
  pick("Left bottom: Empty", "Choose app…")
  check("t163 not app", world.alerted == "/tmp is not an app with a bundle ID",
    tostring(world.alerted))
  world.chosenFile = { ["1"] = "/Applications/Zoom.app" }
  pick("Left bottom: Empty", "Choose app…")
  check("t163 ignored", world.alerted == "test.Zoom is in ignoreBundles", tostring(world.alerted))
  check("t163 unchanged", anchors.assignments()["left-bottom"] == before and #world.opened == 0)
  local ok, problem = anchors.assignPath("left-bottom", nil)
  check("t163 nil path", ok == nil and problem == "nil is not an app with a bundle ID")
end



-- Test 164: A pick from a slot list opens the app like a Dock click, and Empty and Pin
-- frontmost app open nothing.
tests[#tests + 1] = function()
  install(ultrawide())
  addWin("Slack", leftFull)
  addWin("Finder", { x = 1000, y = 100, w = 600, h = 400 })
  world.focused = world.windows[1]
  anchors.start()
  pick("Left bottom: Empty", "Finder")
  check("t164 locked", anchors.assignments()["left-bottom"] == "test.Finder")
  check("t164 opened", table.concat(world.opened, ",") == "/usr/bin/open -b test.Finder",
    table.concat(world.opened, ","))
  pick("Left bottom: Finder", "Empty")
  check("t164 empty", anchors.assignments()["left-bottom"] == "" and #world.opened == 1)
  anchors.lock("left-bottom", "")
  check("t164 lock empty", #world.opened == 1)
  pick("Anchor frontmost app (Finder)", "Right bottom")
  check("t164 frontmost", anchors.assignments()["right-bottom"] == "test.Finder"
    and #world.opened == 1)
end

-- Test 165: A left pin that will not shrink to the strip keeps its own width at the
-- edge, is logged once and is not moved again.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Slack", { x = 300, y = 100, w = 900, h = 700 })
  w.minW = 668
  anchors.start()
  frameIs("t165 placed", w, { x = 0, y = 25, w = 668, h = 1415 })
  for _ = 1, 8 do
    world.clock = world.clock + 5
    world.poll()
  end
  check("t165 one move", w.moves == 1, "moves " .. w.moves)
  check("t165 logged", said("keeps a size of at least 668x1415") == 1)
  check("t165 not held", said("keeps moving back") == 0)
end

-- Test 166: A right pin that will not shrink keeps its right edge on the screen edge.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("iTerm2", { x = 3000, y = 100, w = 900, h = 700 })
  w.minW = 2500
  anchors.start()
  frameIs("t166 placed", w, { x = 2620, y = 25, w = 2500, h = 1415 })
  world.clock = world.clock + 5
  world.poll()
  check("t166 two moves", w.moves == 2, "moves " .. w.moves)
end

-- Test 167: A bottom row that will not shrink in height keeps its bottom edge.
tests[#tests + 1] = function()
  install(ultrawide())
  addWin("Slack", leftFull)
  local w = addWin("Finder", { x = 1000, y = 100, w = 600, h = 400 })
  w.minH = 800
  anchors.start()
  anchors.assign("left-bottom", "test.Finder")
  anchors.moor()
  frameIs("t167 placed", w, { x = 0, y = 640, w = 512, h = 800 })
  local moves = w.moves
  world.clock = world.clock + 5
  world.poll()
  check("t167 settled", w.moves == moves, "moves " .. w.moves)
end

-- Test 168: A learned minimum holds the strip open through width changes, narrowing
-- below it is refused, and Re-moor now tries the chosen width again.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Slack", { x = 300, y = 100, w = 900, h = 700 })
  w.minW = 668
  anchors.start()
  local moves = w.moves
  anchors.setWidths(11, 45)
  frameIs("t168 held", w, { x = 0, y = 25, w = 668, h = 1415 })
  check("t168 no retry", w.moves == moves, "moves " .. w.moves)
  check("t168 narrower refused", anchors.step("left", -1) == false)
  check("t168 wider ok", anchors.step("left", 1) == true)
  anchors.setWidths(20, 45)
  frameIs("t168 wider", w, { x = 0, y = 25, w = 1024, h = 1415 })
  w.minW = 400
  anchors.setWidths(10, 45)
  frameIs("t168 still held", w, { x = 0, y = 25, w = 668, h = 1415 })
  click("Re-moor now")
  frameIs("t168 retried", w, leftFull)
end

-- Test 169: What was learned goes when the window closes and on Re-moor now.
tests[#tests + 1] = function()
  install(ultrawide())
  local w = addWin("Slack", { x = 300, y = 100, w = 900, h = 700 })
  w.minW = 668
  anchors.start()
  table.remove(world.windows, 1)
  world.poll()
  table.insert(world.windows, 1, w)
  w.minW = nil
  world.poll()
  frameIs("t169 closed", w, leftFull)
  w.minW = 668
  w.f = { x = 300, y = 100, w = 900, h = 700 }
  world.poll()
  w.minW = nil
  click("Re-moor now")
  frameIs("t169 re-moor", w, leftFull)
end

-- Test 170: A pin that will not shrink widens its strip, the channel starts after it,
-- free windows stay out from under it, and nothing moves on later passes.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", { x = 300, y = 100, w = 900, h = 700 })
  slack.minW = 668
  local safari = addWin("Safari", { x = 520, y = 100, w = 800, h = 600 })
  anchors.start()
  world.poll()
  check("t170 channel", anchors.channel(world.screens[1]).x == 668,
    "x " .. anchors.channel(world.screens[1]).x)
  check("t170 free window clear", safari.f.x >= 668, "x " .. safari.f.x)
  local sm, fm = slack.moves, safari.moves
  for _ = 1, 5 do
    world.clock = world.clock + 5
    world.poll()
  end
  check("t170 still", slack.moves == sm and safari.moves == fm,
    "moves " .. slack.moves .. " " .. safari.moves)
  check("t170 slot", anchors.slotFrame(world.screens[1], "left-top").w == 668)
end

-- Test 171: The Widths folder says which app holds a side and disables steps and presets
-- below it.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", { x = 300, y = 100, w = 900, h = 700 })
  slack.minW = 668
  anchors.start()
  world.poll()
  check("t171 label", item("Left 13% in use: Slack needs 668 pt") ~= nil
    and item("Left 13% in use: Slack needs 668 pt").disabled == true)
  check("t171 channel label", item("Channel 42%") ~= nil)
  check("t171 narrower off", item("Left narrower").disabled == true)
  check("t171 wider on", item("Left wider").disabled == false)
  check("t171 preset off", item("Left 10%, right 45%").disabled == true)
  check("t171 preset on", item("Left 15%, right 40%").disabled == false)
end

-- Test 172: Pins that would squeeze the channel under 10 percent share what room is left.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", { x = 300, y = 100, w = 900, h = 700 })
  slack.minW = 2500
  local term = addWin("iTerm2", { x = 3000, y = 100, w = 900, h = 700 })
  term.minW = 2500
  anchors.start()
  world.poll()
  local ch = anchors.channel(world.screens[1])
  check("t172 channel kept", ch.w >= 511, "w " .. ch.w)
end

-- Test 173: A pin moved by hand is released once with an alert, left where it was put,
-- and re-moored by Restore, by Re-moor app, and by Re-moor now.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  local moved = { x = 900, y = 200, w = 700, h = 600 }
  -- moveByHand puts slack at moved once the grace has passed and lets moorings look.
  local function moveByHand()
    world.clock = world.clock + 3
    world.poll()
    slack.f = copy(moved)
    world.poll()
  end
  moveByHand()
  frameIs("t173 left alone", slack, moved)
  check("t173 alert", world.alerted ~= nil and world.alerted:find("Slack released", 1, true) ~= nil
    and world.alerted:find("⌃⌥⌫", 1, true) ~= nil and world.alerted:find("Re-moor Slack", 1, true) ~= nil,
    tostring(world.alerted))
  check("t173 logged once", said("moved by hand: released") == 1)
  world.clock = world.clock + 10
  world.poll()
  frameIs("t173 still alone", slack, moved)
  check("t173 alerted once", world.alerts == 1, "alerts " .. tostring(world.alerts))
  check("t173 menu item", item("Re-moor Slack") ~= nil)
  focus(slack)
  press("ctrl+alt", "delete")
  frameIs("t173 restore", slack, leftFull)
  check("t173 item gone", item("Re-moor Slack") == nil)
  moveByHand()
  click("Re-moor Slack")
  frameIs("t173 menu re-moor", slack, leftFull)
  moveByHand()
  click("Re-moor now")
  frameIs("t173 re-moor now", slack, leftFull)
end

-- Test 174: Width, height and focus changes re-place a pin and never release it, and a
-- pin settling on its own within the grace is put back.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.config.pins[1].expandPct = 30
  anchors.start()
  world.clock = world.clock + 3
  anchors.setWidths(15, 40)
  frameIs("t174 widths", slack, { x = 0, y = 25, w = 768, h = 1415 })
  world.clock = world.clock + 3
  focus(slack)
  world.onEvent()
  frameIs("t174 focus", slack, { x = 0, y = 25, w = 1536, h = 1415 })
  check("t174 no release", world.alerted == nil, tostring(world.alerted))
  world.clock = world.clock + 1
  slack.f.w = 900
  world.poll()
  frameIs("t174 settled back", slack, { x = 0, y = 25, w = 1536, h = 1415 })
  check("t174 still no release", world.alerted == nil)
end

-- Test 175: Maximize lifts a pin over its strip and the channel at full height, stopping
-- at the other strip, and lowers it again. Restore also lowers it.
tests[#tests + 1] = function()
  install(ultrawide())
  local notes, slack = stackedLeft()
  local term = addWin("iTerm2", { x = 3000, y = 100, w = 900, h = 700 })
  anchors.start()
  frameIs("t175 slot", slack, leftBottom)
  focus(slack)
  press("ctrl+alt", "return")
  frameIs("t175 lifted", slack, { x = 0, y = 25, w = 2816, h = 1415 })
  check("t175 raised", world.focused == slack)
  world.clock = world.clock + 5
  world.poll()
  frameIs("t175 stays lifted", slack, { x = 0, y = 25, w = 2816, h = 1415 })
  frameIs("t175 notes kept", notes, leftTop)
  press("ctrl+alt", "return")
  frameIs("t175 lowered", slack, leftBottom)
  focus(term)
  press("ctrl+alt", "return")
  frameIs("t175 right lifted", term, { x = 512, y = 25, w = 4608, h = 1415 })
  press("ctrl+alt", "delete")
  frameIs("t175 restore lowers", term, rightFull)
end

-- Test 176: The Lift folder lists each pin, checks the lifted one, and toggles it.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  addWin("iTerm2", rightFull)
  anchors.start()
  check("t176 folder", titles(folder("Lift")) == "iTerm2,Slack", titles(folder("Lift")))
  click("Slack")
  frameIs("t176 lifted", slack, { x = 0, y = 25, w = 2816, h = 1415 })
  check("t176 checked", item("Slack").checked == true)
  click("Slack")
  frameIs("t176 lowered", slack, leftFull)
  local other = addWin("Safari", { x = 1000, y = 200, w = 800, h = 600 })
  focus(other)
  click("Slack")
  check("t176 raised", world.focused == slack)
  world.clock = world.clock + 3
  world.poll()
  slack.f = { x = 900, y = 200, w = 700, h = 600 }
  world.poll()
  check("t176 released unchecked", item("Slack").checked == false)
  click("Slack")
  frameIs("t176 lift re-moors", slack, { x = 0, y = 25, w = 2816, h = 1415 })
  install(ultrawide())
  anchors.start()
  check("t176 empty", titles(folder("Lift")) == "No anchored windows")
end

-- Test 177: A click on a pin's green button is swallowed, down and up, and lifts the pin.
-- Clicks elsewhere pass, and the button rect is asked for only when the frame changes.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  for _ = 1, 4 do
    world.clock = world.clock + 1
    world.poll()
  end
  check("t177 asked once", slack.zoomAsks == 1, "asks " .. tostring(slack.zoomAsks))
  -- send fires a mouse event of type t at point p and returns whether it passed on.
  local function send(t, p)
    world.mousePos = p
    return world.tap({ getType = function() return t end, getFlags = function() return {} end })
  end
  check("t177 down eaten", send(1, { x = 60, y = 40 }) == true)
  check("t177 up eaten", send(2, { x = 60, y = 40 }) == true)
  frameIs("t177 lifted", slack, { x = 0, y = 25, w = 2816, h = 1415 })
  check("t177 elsewhere passes", send(1, { x = 300, y = 300 }) == false
    and send(2, { x = 300, y = 300 }) == false)
  check("t177 new rect", send(1, { x = 60, y = 40 }) == true and send(2, { x = 60, y = 40 }) == true)
  frameIs("t177 lowered", slack, leftFull)
  click("⚓ Raise anchor (let windows drift)")
  check("t177 frozen passes", send(1, { x = 60, y = 40 }) == false)
end

-- Test 178: Pins moved while frozen or by a display change are re-moored, not released,
-- and a closed pin leaves no release, lift or green button behind.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  world.clock = world.clock + 3
  world.poll()
  click("⚓ Raise anchor (let windows drift)")
  slack.f = { x = 900, y = 200, w = 700, h = 600 }
  world.clock = world.clock + 3
  click("⚓ Drop anchor (hold the layout)")
  frameIs("t178 resume", slack, leftFull)
  world.clock = world.clock + 3
  world.poll()
  slack.f = { x = 900, y = 200, w = 700, h = 600 }
  world.onScreens()
  frameIs("t178 display change", slack, leftFull)
  check("t178 no alert", world.alerted == nil, tostring(world.alerted))
  focus(slack)
  press("ctrl+alt", "return")
  table.remove(world.windows, 1)
  world.focused = nil
  world.poll()
  world.mousePos = { x = 60, y = 40 }
  check("t178 closed passes", world.tap({ getType = function() return 1 end,
    getFlags = function() return {} end }) == false)
  world.tap({ getType = function() return 2 end, getFlags = function() return {} end })
  table.insert(world.windows, 1, slack)
  slack.f = copy(leftFull)
  world.poll()
  frameIs("t178 back in slot", slack, leftFull)
end

-- Test 179: A tab torn out of iTerm into a new window stays where it lands, even once it
-- becomes the main window, and takes the slot only when the held window closes.
tests[#tests + 1] = function()
  install(ultrawide())
  local term = addWin("iTerm2", rightFull)
  anchors.start()
  local torn = addWin("iTerm2", { x = 1200, y = 300, w = 700, h = 500 })
  focus(torn)
  term.secondary = true
  world.onEvent()
  world.clock = world.clock + 5
  world.poll()
  check("t179 torn stays", torn.moves == 0, "moves " .. torn.moves)
  frameIs("t179 held stays", term, rightFull)
  for i, w in ipairs(world.windows) do
    if w == term then table.remove(world.windows, i) break end
  end
  world.poll()
  world.poll()
  frameIs("t179 takes the slot", torn, rightFull)
end

-- Test 181: A pin released by a move it did not make keeps its green button, and a click
-- there re-moors it instead of starting fullscreen. The alert names the green button.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  anchors.start()
  world.clock = world.clock + 3
  world.poll()
  -- send fires a mouse event of type t at point p and returns whether it was swallowed.
  local function send(t, p)
    world.mousePos = p
    return world.tap({ getType = function() return t end, getFlags = function() return {} end })
  end
  check("t181 lift", send(1, { x = 60, y = 40 }) == true and send(2, { x = 60, y = 40 }) == true)
  frameIs("t181 lifted", slack, { x = 0, y = 25, w = 2816, h = 1415 })
  world.clock = world.clock + 3
  world.poll()
  slack.f = { x = 0, y = 25, w = 5120, h = 1415 }
  world.poll()
  check("t181 released", item("Re-moor Slack") ~= nil)
  check("t181 released click eaten", send(1, { x = 60, y = 40 }) == true)
  send(2, { x = 60, y = 40 })
  frameIs("t181 home at once", slack, leftFull)
  world.clock = world.clock + 3
  world.poll()
  slack.f = { x = 0, y = 25, w = 5120, h = 1415 }
  world.poll()
  check("t181 alert", world.alerted ~= nil
    and world.alerted:find("click its green button, press ⌃⌥⌫, or choose Re-moor Slack", 1, true) ~= nil,
    tostring(world.alerted))
  world.poll()
  check("t181 home click eaten", send(1, { x = 60, y = 40 }) == true and send(2, { x = 60, y = 40 }) == true)
  frameIs("t181 home", slack, leftFull)
  check("t181 not released", item("Re-moor Slack") == nil)
  check("t181 no fullscreen", slack.full ~= true)
  world.clock = world.clock + 3
  world.poll()
  check("t181 lifts again", send(1, { x = 60, y = 40 }) == true and send(2, { x = 60, y = 40 }) == true)
  frameIs("t181 lifted again", slack, { x = 0, y = 25, w = 2816, h = 1415 })
  world.clock = world.clock + 3
  world.poll()
  slack.f = { x = 900, y = 200, w = 700, h = 600 }
  world.poll()
  check("t181 old rect passes", send(1, { x = 60, y = 40 }) == false)
  send(2, { x = 60, y = 40 })
  check("t181 moved rect eaten", send(1, { x = 957, y = 211 }) == true and send(2, { x = 957, y = 211 }) == true)
  frameIs("t181 home again", slack, leftFull)
end

-- Test 182: Unanchor all apps empties every slot and frees the windows into the channel, is
-- off once nothing is anchored, and Reset to defaults brings the config apps back.
tests[#tests + 1] = function()
  install(ultrawide())
  local slack = addWin("Slack", leftFull)
  local term = addWin("iTerm2", rightFull)
  anchors.start()
  check("t182 on", item("Unanchor all apps").disabled == false)
  click("Unanchor all apps")
  local picks = anchors.assignments()
  check("t182 empty", picks["left-top"] == "" and picks["left-bottom"] == ""
    and picks["right-top"] == "" and picks["right-bottom"] == "")
  world.poll()
  local ch = anchors.channel(world.screens[1])
  check("t182 slack free", slack.f.x >= ch.x and slack.f.x + slack.f.w <= ch.x + ch.w,
    string.format("x %g w %g", slack.f.x, slack.f.w))
  check("t182 term free", term.f.x >= ch.x and term.f.x + term.f.w <= ch.x + ch.w,
    string.format("x %g w %g", term.f.x, term.f.w))
  check("t182 rows empty", item("Left top: Empty") ~= nil and item("Right top: Empty") ~= nil)
  check("t182 off", item("Unanchor all apps").disabled == true)
  click("Reset to defaults")
  world.poll()
  frameIs("t182 slack back", slack, leftFull)
  frameIs("t182 term back", term, rightFull)
end

-- unhinted returns the titles of entries in items, at any depth, whose hover hint is wrong:
-- a folder has one, which would cover its open submenu, or any other entry lacks a sentence
-- starting with a capital and ending with a period.
local function unhinted(items, out)
  out = out or {}
  for _, it in ipairs(items) do
    local hint = it.tooltip
    if it.menu then
      if hint ~= nil then
        out[#out + 1] = it.title
      end
      unhinted(it.menu, out)
    elseif it.title ~= "-" and (type(hint) ~= "string" or not hint:match("^%u") or not hint:match("%.$")) then
      out[#out + 1] = it.title
    end
  end
  return out
end

-- Test 180: Every menu entry that is not a folder has a hover hint and no folder has one, in
-- a bare world, a world that shows every conditional entry, frozen, and when the menu fails.
tests[#tests + 1] = function()
  install(ultrawide())
  anchors.start()
  check("t180 bare branches", item("No anchored windows") ~= nil and item("No saved workspaces") ~= nil
    and item("No sizes in the config") ~= nil)
  local missing = unhinted(world.bar.menu())
  check("t180 bare", #missing == 0, table.concat(missing, ", "))

  install(ultrawide())
  world.images["/img/wave.png"] = true
  anchors.config.icons = { { name = "Wavy", image = "/img/wave.png" } }
  anchors.config.sizes = { { title = "Video", width = 1280, height = 720 } }
  local slack = addWin("Slack", { x = 300, y = 100, w = 900, h = 700 })
  slack.minW = 668
  local term = addWin("iTerm2", rightFull)
  anchors.start()
  world.poll()
  world.chosenFile = { ["1"] = "/Applications/Calendar.app" }
  pick("Left bottom: Empty", "Choose app…")
  saveAs("Desk")
  world.clock = world.clock + 3
  world.poll()
  term.f = { x = 1200, y = 200, w = 900, h = 600 }
  world.poll()
  world.trusted = false
  for _, title in ipairs({ "⚠️ Grant Accessibility access", "Re-moor iTerm2", "Yours",
    "Left 13% in use: Slack needs 668 pt", "Calendar", "Desk", "Video", "Slack" }) do
    check("t180 shows " .. title, item(title) ~= nil)
  end
  missing = unhinted(world.bar.menu())
  check("t180 full", #missing == 0, table.concat(missing, ", "))
  click("⚓ Raise anchor (let windows drift)")
  missing = unhinted(world.bar.menu())
  check("t180 frozen", #missing == 0, table.concat(missing, ", "))

  hs.application.frontmostApplication = function() error("boom") end
  local failed = world.bar.menu()
  check("t180 failed menu", #failed == 1 and failed[1].title == "Menu failed, see Console")
  missing = unhinted(failed)
  check("t180 failed", #missing == 0, table.concat(missing, ", "))
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
