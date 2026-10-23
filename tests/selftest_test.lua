-- selftest_test drives selftest.lua against a fake Hammerspoon, a fake TextEdit and a small
-- model of moorings that pins the held window and keeps free windows in the channel. Run it
-- from the repo root with: lua tests/selftest_test.lua

package.path = "./?.lua;" .. package.path

local failures, passes = 0, 0
local world, T

-- check records a failure when cond is false.
local function check(name, cond, msg)
  if cond then
    passes = passes + 1
  else
    failures = failures + 1
    print("FAIL " .. name .. ": " .. (msg or "condition false"))
  end
end

-- copy returns a plain copy of a frame.
local function copy(f)
  return { x = f.x, y = f.y, w = f.w, h = f.h }
end

-- same reports whether two frames match within a point.
local function same(a, b)
  return math.abs(a.x - b.x) <= 1 and math.abs(a.y - b.y) <= 1
    and math.abs(a.w - b.w) <= 1 and math.abs(a.h - b.h) <= 1
end

-- screenFrame is the usable frame of the fake ultrawide.
local screenFrame = { x = 0, y = 25, w = 5120, h = 1415 }

-- strip is where the fake moorings pins TextEdit on the left side.
local strip = { x = 0, y = 25, w = 512, h = 1415 }

-- channel is the fake channel while the left side holds a window.
local channel = { x = 512, y = 25, w = 2304, h = 1415 }

local Win = {}
Win.__index = Win

-- Win:id returns the window id.
function Win:id() return self.wid end

-- Win:frame returns the current frame.
function Win:frame() return copy(self.f) end

-- Win:setFrame moves the window as the owner would.
function Win:setFrame(f) self.f = copy(f) end

-- Win:close closes the window unless the fake says it will not close.
function Win:close()
  if world.stuckClose then return end
  self.closed = true
end

-- Win:focus records the focused window.
function Win:focus() world.focused = self end

-- Win:isStandard reports a standard window.
function Win:isStandard() return true end

-- Win:zoomButtonRect returns the green button rect.
function Win:zoomButtonRect() return { x = self.f.x + 57, y = self.f.y + 11, w = 16, h = 16 } end

-- open lists TextEdit's open windows.
local function open()
  local list = {}
  for _, w in ipairs(world.windows) do
    if not w.closed then list[#list + 1] = w end
  end
  return list
end

-- addWin opens a TextEdit window at f, a panel when panel is true.
local function addWin(f, panel)
  world.nextID = world.nextID + 1
  local w = setmetatable({ wid = world.nextID, f = copy(f), panel = panel }, Win)
  world.windows[#world.windows + 1] = w
  return w
end

-- assigned reports whether TextEdit sits in a slot.
local function assigned()
  for _, b in pairs(world.slots) do
    if b == "com.apple.TextEdit" then return true end
  end
  return false
end

-- held returns the window the fake moorings pins: the one it holds, or else the first
-- document, or a panel too when the fake is told to hold pickers.
local function held()
  if not assigned() or not world.running then return nil end
  local cur = world.holder and world.windows[world.holder]
  if cur and not cur.closed then return cur end
  for _, w in ipairs(open()) do
    if not w.panel or world.holdsPicker then
      world.holder = w.wid
      return w
    end
  end
  world.holder = nil
  return nil
end

-- simulate runs one pass of the fake moorings.
local function simulate()
  local h = held()
  if world.paused then return end
  if h then
    local last = world.lastAt[h.wid]
    if last and not same(h.f, last) and not world.neverRelease then
      world.released[h.wid] = true
    end
    if not world.released[h.wid] and not world.brokenPin then
      h.f = copy(strip)
      world.lastAt[h.wid] = copy(strip)
    end
  end
  for _, w in ipairs(open()) do
    if w ~= h and not w.panel and not world.straysFree then
      w.f.x = math.max(w.f.x, channel.x)
    end
  end
end

-- fakeApp returns the fake TextEdit while it runs.
local function fakeApp()
  if not world.running then return nil end
  return {
    allWindows = function() return open() end,
    activate = function() world.activated = true end,
    kill = function()
      world.killed = true
      if world.stubborn then return end
      world.running = false
      for _, w in ipairs(world.windows) do w.closed = true end
    end,
    kill9 = function()
      world.forced = true
      if world.stubborn == "always" then return end
      world.running = false
      for _, w in ipairs(world.windows) do w.closed = true end
    end,
  }
end

-- host builds the fake anchors module the selftest drives.
local function host()
  return {
    config = { tolerance = 2 },
    slotNames = {
      { key = "left-top", side = "left", row = "top" },
      { key = "left-bottom", side = "left", row = "bottom" },
      { key = "right-top", side = "right", row = "top" },
      { key = "right-bottom", side = "right", row = "bottom" },
    },
    now = function() return world.clock end,
    log = function(m) world.logs[#world.logs + 1] = m end,
    safe = function(fn) return fn end,
    near = same,
    path = function(f) return "/h/.hammerspoon/moorings/" .. f end,
    ultrawide = function()
      if world.noUltrawide then return nil end
      return { frame = function() return copy(screenFrame) end }
    end,
    channel = function() return copy(channel) end,
    inUse = function()
      return held() and 10 or 0, 45
    end,
    pinned = function(w) local h = held() return h ~= nil and h.wid == w.wid end,
    target = function(w) return world.lastAt[w.wid] end,
    released = function(w) return world.released[w.wid] == true end,
    assignments = function()
      local out = {}
      for k, v in pairs(world.slots) do out[k] = v end
      return out
    end,
    assign = function(key, bundle)
      world.assigns, world.slotSeen = world.assigns + 1, key
      world.slots[key] = bundle
    end,
    setPaused = function(on)
      world.paused = on
      world.lastAt = {}
      simulate()
    end,
    snapshotLayout = function()
      local slots = {}
      for k, v in pairs(world.slots) do slots[k] = v end
      return { slots = slots, paused = world.paused }
    end,
    restoreLayout = function(saved)
      if world.restoreFails then error("restore broke", 0) end
      world.slots, world.paused, world.restored = saved.slots, saved.paused, true
    end,
    keepAlive = function() return world.keepAlive end,
  }
end

-- install loads a fresh selftest into a fake world. Slack holds the right top slot.
local function install()
  world = {
    clock = 1000, timers = {}, windows = {}, nextID = 0, logs = {}, files = {}, results = {},
    released = {}, lastAt = {}, assigns = 0, docs = 0, trusted = true, running = false,
    paused = false,
    slots = { ["left-top"] = "", ["left-bottom"] = "", ["right-top"] = "com.tinyspeck.slackmacgap",
      ["right-bottom"] = "" },
    plist = "<plist/>", plistOnDisk = "<plist/>", loaded = true,
  }
  hs = {
    accessibilityState = function() return world.trusted end,
    urlevent = { bind = function(name, fn) world.bound, world.urlFn = name, fn end },
    json = {
      encode = function(t)
        world.results[#world.results + 1] = t
        return "json"
      end,
    },
  }
  package.loaded.keepalive = {
    label = "moorings.keepalive",
    plistPath = function() return "/h/Library/LaunchAgents/moorings.keepalive.plist" end,
    plist = function(sentinel)
      world.sentinel = sentinel
      return world.plist
    end,
    readFile = function() return world.plistOnDisk end,
    loaded = function() return world.loaded end,
  }
  package.loaded.updates = { version = "9.9.9" }
  package.loaded.selftest = nil
  T = require("selftest")
  T.after = function(s, fn)
    world.timers[#world.timers + 1] = { at = world.clock + s, fn = fn }
  end
  T.launch = function()
    world.launches = (world.launches or 0) + 1
    if world.noLaunch then return end
    world.timers[#world.timers + 1] = {
      at = world.clock + 0.5,
      fn = function()
        world.running = true
        if world.launchPanel then addWin({ x = 900, y = 200, w = 700, h = 500 }, true) end
        if not world.noDocument then addWin({ x = 100, y = 100, w = 600, h = 400 }) end
      end,
    }
  end
  T.focused = function()
    if world.focusFails then return nil end
    return world.focused
  end
  T.frontAt = function()
    if world.coveredFor and world.coveredFor > 0 then
      world.coveredFor = world.coveredFor - 1
      return { id = function() return 999 end }
    end
    return world.focused
  end
  T.store = function(saved) world.stored = saved end
  T.stored = function() return world.stored end
  T.forget = function() world.stored = nil end
  T.app = fakeApp
  T.openPanel = function(w) return w.panel == true end
  T.click = function(p)
    world.clicks = (world.clicks or 0) + 1
    local h = held()
    if h and not world.deadButton then
      local r = h:zoomButtonRect()
      if p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h then
        world.released[h.wid] = nil
        world.lastAt[h.wid] = nil
      end
    end
  end
  T.key = function(mods, key, app)
    if mods[1] == "cmd" and key == "o" and not world.noPicker then
      addWin({ x = 400, y = 200, w = 700, h = 500 }, true)
    elseif mods[1] == "cmd" and key == "n" and world.running then
      if world.noDocument or (world.docLimit and world.docs >= world.docLimit) then return end
      world.docs = world.docs + 1
      world.timers[#world.timers + 1] = {
        at = world.clock + 0.3,
        fn = function() addWin({ x = 100, y = 100, w = 600, h = 400 }) end,
      }
    elseif key == "escape" and app == nil then
      world.escapes = (world.escapes or 0) + 1
      local f = world.focused
      if f and f.panel and not f.closed and not world.stuckClose then f.closed = true end
    end
  end
  T.write = function(path, text)
    world.files[path] = text
    return true
  end
  T.logDir = function() return "/h/Library/Logs/moorings" end
  T.attach(host())
end

-- pump fires timers in time order, running a pass of the fake moorings before each.
local function pump()
  for _ = 1, 100000 do
    if #world.timers == 0 then return end
    table.sort(world.timers, function(a, b) return a.at < b.at end)
    local t = table.remove(world.timers, 1)
    world.clock = math.max(world.clock, t.at)
    simulate()
    t.fn()
  end
  error("timers never ran out")
end

-- run starts a run through the URL and pumps it to the end, returning its result.
local function run(params)
  world.urlFn("moorings-selftest", params or { run = "r1" })
  pump()
  return world.results[#world.results]
end

-- named returns the check called name in result, or nil.
local function named(result, name)
  for _, c in ipairs(result.checks) do
    if c.name == name then return c end
  end
  return nil
end

-- failedNames lists the checks result failed.
local function failedNames(result)
  local out = {}
  for _, c in ipairs(result.checks) do
    if not c.ok then out[#out + 1] = c.name end
  end
  return out
end

local tests = {}

-- Test 0: attach binds the selftest URL, and a missing, odd or long run id starts nothing.
tests[#tests + 1] = function()
  install()
  check("t0 bound", world.bound == "moorings-selftest")
  local bad = { {}, { run = "a b" }, { run = "x/../y" }, { run = string.rep("a", 65) } }
  for _, params in ipairs(bad) do
    world.urlFn("moorings-selftest", params)
  end
  world.urlFn("moorings-selftest", nil)
  pump()
  check("t0 nothing ran", #world.results == 0 and world.assigns == 0)
  check("t0 logged", #world.logs == 5 and world.logs[1]:find("run=", 1, true) ~= nil)
end

-- Test 1: A run against a working moorings passes every check, skips what does not apply,
-- writes the result where the command looks, and puts the layout back.
tests[#tests + 1] = function()
  install()
  local r = run({ run = "20261022-1-77" })
  check("t1 pass", r.pass == true and r.error == nil, table.concat(failedNames(r), "; "))
  check("t1 count", #r.checks == 12, tostring(#r.checks))
  check("t1 run and version", r.run == "20261022-1-77" and r.version == "9.9.9")
  check("t1 no planted", r.planted == nil)
  check("t1 file", world.files["/h/Library/Logs/moorings/selftest-20261022-1-77.json"] == "json")
  check("t1 keep-alive skipped", named(r, "restart helper is loaded and current").skipped == true)
  check("t1 empty side used", world.restored and world.slots["left-top"] == ""
    and world.slots["right-top"] == "com.tinyspeck.slackmacgap" and world.paused == false)
  check("t1 TextEdit quit", world.killed == true and world.running == false)
  check("t1 picker shown", named(r, "open picker is not held").ok)
  check("t1 clicked", world.clicks == 1)
  check("t1 summary logged",
    world.logs[#world.logs] == "selftest 20261022-1-77: 12 checks, 0 failed")
end

-- Test 2: The negative control fails exactly the planted check and names it in the result.
tests[#tests + 1] = function()
  install()
  local r = run({ run = "c1", control = "1" })
  local failed = failedNames(r)
  check("t2 one failure", #failed == 1 and failed[1] == T.planted, table.concat(failed, "; "))
  check("t2 planted named", r.planted == T.planted and r.pass == false)
  check("t2 detail", named(r, T.planted).detail:find("want {40,25,512,1415}", 1, true) ~= nil,
    named(r, T.planted).detail)
end

-- Test 3: A run refuses to start, and leaves the layout untouched, without Accessibility, an
-- ultrawide, a quit TextEdit or an empty slot, or with TextEdit already anchored.
tests[#tests + 1] = function()
  local cases = {
    { set = function() world.trusted = false end, want = "Accessibility" },
    { set = function() world.noUltrawide = true end, want = "ultrawide" },
    { set = function() world.running = true end, want = "Quit it first" },
    { set = function() world.slots["left-top"] = "com.apple.TextEdit" end, want = "is anchored" },
    {
      set = function()
        for k in pairs(world.slots) do world.slots[k] = "test.app" end
      end,
      want = "every slot is taken",
    },
  }
  for i, c in ipairs(cases) do
    install()
    c.set()
    local r = run()
    check("t3 refused " .. i, r.pass == false and r.error and r.error:find(c.want, 1, true) ~= nil,
      tostring(r.error))
    check("t3 untouched " .. i, world.assigns == 0 and not world.restored and #r.checks == 0)
  end
end

-- Test 4: A side shared with another app is only used when no side is empty, and then the
-- side check is skipped instead of failing.
tests[#tests + 1] = function()
  install()
  world.slots["left-top"] = "test.left"
  local r = run()
  check("t4 pass", r.pass == true, table.concat(failedNames(r), "; "))
  check("t4 borrowed left bottom", world.slotSeen == "left-bottom", tostring(world.slotSeen))
  local c = named(r, "an anchored app with no window frees its side")
  check("t4 side skipped", c.skipped == true and c.detail == "another app shares the left side",
    c.detail)
end

-- Test 5: A failure halfway still closes the windows, quits TextEdit, puts the layout back,
-- keeps the checks already made and lets the next run start.
tests[#tests + 1] = function()
  install()
  world.slots["left-top"], world.paused = "", true
  world.docLimit = 0
  local r = run()
  check("t5 error", r.error == "the new TextEdit document did not show", tostring(r.error))
  check("t5 first check kept", #r.checks == 1 and r.checks[1].ok)
  check("t5 restored", world.restored and world.paused == true and world.slots["left-top"] == "")
  check("t5 quit", world.killed == true)
  install()
  world.noDocument = true
  r = run()
  check("t5 no document", r.error == "the new TextEdit document did not show", tostring(r.error))
  check("t5 restored again", world.restored and world.killed)
  r = run({ run = "r2" })
  check("t5 next run starts", r.run == "r2")
  install()
  world.noLaunch = true
  r = run()
  check("t5 no launch", r.error == "the new TextEdit document did not show", tostring(r.error))
  check("t5 no launch restored", world.restored and #r.checks == 0)
end

-- Test 6: Each broken behavior fails its own check with what was seen.
tests[#tests + 1] = function()
  local cases = {
    { set = function() world.brokenPin = true end, want = T.planted },
    {
      set = function() world.straysFree = true end,
      want = "second window stays free in the channel",
    },
    { set = function() world.holdsPicker = true end, want = "open picker is not held" },
    { set = function() world.noPicker = true end, want = "open picker is not held" },
    {
      set = function() world.neverRelease = true end,
      want = "moving the anchored window releases it",
    },
    {
      set = function() world.deadButton = true end,
      want = "green button puts a released window back",
    },
  }
  for i, c in ipairs(cases) do
    install()
    c.set()
    local r = run()
    local hit = named(r, c.want)
    check("t6 fails " .. i, r.pass == false and hit and not hit.ok and hit.detail ~= "",
      table.concat(failedNames(r), "; "))
    check("t6 cleaned " .. i, world.restored and world.killed)
  end
end

-- Test 7: The restart helper check passes only while its plist matches and launchd has it.
tests[#tests + 1] = function()
  local name = "restart helper is loaded and current"
  install()
  world.keepAlive = true
  local r = run()
  check("t7 current", named(r, name).ok and not named(r, name).skipped)
  check("t7 sentinel", world.sentinel == "/h/.hammerspoon/moorings/anchors.lua")
  install()
  world.keepAlive, world.plistOnDisk = true, "<old/>"
  check("t7 stale", not named(run(), name).ok)
  install()
  world.keepAlive, world.loaded = true, false
  r = run()
  check("t7 not loaded", not named(r, name).ok and named(r, name).detail:find("launchd", 1, true))
end

-- Test 8: A second start while a run is going is refused, and a panel TextEdit shows at
-- launch is dismissed before the first check.
tests[#tests + 1] = function()
  install()
  world.urlFn("moorings-selftest", { run = "a" })
  world.urlFn("moorings-selftest", { run = "b" })
  check("t8 refused", world.logs[1] == "selftest b not started: another run is going")
  pump()
  check("t8 one result", #world.results == 1 and world.results[1].run == "a")
  install()
  world.launchPanel = true
  local r = run()
  check("t8 launch panel dismissed", r.pass == true, table.concat(failedNames(r), "; "))
  install()
  world.launchPanel, world.stuckClose = true, true
  r = run()
  check("t8 stuck panel stops the run", r.error == "the TextEdit open panel would not close",
    tostring(r.error))
  install()
  world.launchPanel, world.focusFails = true, true
  r = run()
  check("t8 unfocused panel stops the run",
    r.error == "the TextEdit open panel would not take focus", tostring(r.error))
  check("t8 no stray escape", world.escapes == nil, tostring(world.escapes))
end

-- Test 9: The URL handler returns before the run touches anything, and a run launches TextEdit
-- once for its first document and makes the rest with Cmd-N, never through AppleScript.
tests[#tests + 1] = function()
  install()
  world.urlFn("moorings-selftest", { run = "d1" })
  check("t9 deferred", #world.timers == 1 and world.assigns == 0 and world.launches == nil)
  pump()
  local r = world.results[1]
  check("t9 pass", r and r.pass == true, r and table.concat(failedNames(r), "; "))
  check("t9 one launch", world.launches == 1, tostring(world.launches))
  check("t9 two with Cmd-N", world.docs == 2, tostring(world.docs))
  check("t9 no AppleScript", T.script == nil)
end

-- Test 10: A run saves the layout before it borrows a slot and forgets it once the layout is
-- back. A run that never finishes leaves it saved, and the next start puts it back.
tests[#tests + 1] = function()
  install()
  run()
  check("t10 forgotten", world.stored == nil and world.restored)
  install()
  world.trusted = false
  run()
  check("t10 refusal stores nothing", world.stored == nil and not world.restored)

  install()
  world.urlFn("moorings-selftest", { run = "crash" })
  for _ = 1, 1000 do
    if world.assigns > 0 then break end
    table.sort(world.timers, function(a, b) return a.at < b.at end)
    local t = table.remove(world.timers, 1)
    world.clock = math.max(world.clock, t.at)
    t.fn()
  end
  check("t10 saved before assign", world.stored and world.stored.slots["left-top"] == ""
    and world.slots["left-top"] == "com.apple.TextEdit")
  world.timers, world.logs = {}, {}
  T.attach(host())
  check("t10 recovered", world.restored and world.slots["left-top"] == ""
    and world.slots["right-top"] == "com.tinyspeck.slackmacgap" and world.stored == nil)
  check("t10 recovery logged", world.logs[1] == "selftest: put back the layout a stopped run left")
  world.restored = false
  T.attach(host())
  check("t10 nothing twice", not world.restored and #world.logs == 1)

  install()
  world.stored = { slots = { ["left-top"] = "x" }, paused = false }
  world.restoreFails = true
  T.attach(host())
  check("t10 failed recovery forgets", world.stored == nil
    and world.logs[1]:find("could not put back", 1, true) ~= nil, tostring(world.logs[1]))
  world.restoreFails = false

  install()
  world.restoreFails = true
  local r = run()
  check("t10 failed cleanup keeps it", world.stored ~= nil and r.error == "restore broke",
    tostring(r.error))
end

-- Test 11: TextEdit that ignores the quit request is forced to quit, and one that survives that
-- too stops the run with the layout already back.
tests[#tests + 1] = function()
  install()
  local r = run()
  check("t11 quit without force", world.running == false and world.forced == nil)
  install()
  world.stubborn = true
  r = run()
  check("t11 forced", r.pass == true and world.forced == true and world.running == false,
    tostring(r.error))
  check("t11 forced restored", world.restored and world.stored == nil)
  install()
  world.stubborn = "always"
  r = run()
  check("t11 would not quit", r.error == "TextEdit would not quit", tostring(r.error))
  check("t11 layout back first", world.restored and world.stored == nil
    and world.slots["left-top"] == "")
end

-- Test 12: The green button is clicked only once the run's window is in front at the button,
-- waiting for it to come forward, and never when another window stays over it.
tests[#tests + 1] = function()
  local green = "green button puts a released window back"
  install()
  world.coveredFor = 5
  local r = run()
  check("t12 waited then clicked", r.pass == true and world.clicks == 1,
    table.concat(failedNames(r), "; "))
  install()
  world.coveredFor = 1000000
  r = run()
  check("t12 never clicked", world.clicks == nil, tostring(world.clicks))
  check("t12 fails", not named(r, green).ok
    and named(r, green).detail:find("covers its green button", 1, true) ~= nil)
end

for i, t in ipairs(tests) do
  local ok, err = pcall(t)
  if not ok then
    failures = failures + 1
    print(string.format("FAIL test %d raised: %s", i - 1, err))
  end
end
print(string.format("%d checks passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
