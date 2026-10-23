-- selftest runs moorings against real windows inside Hammerspoon, so a release is checked for
-- what the fake suites cannot see: real window timing and real app behavior. The moorings
-- selftest command starts a run through a hammerspoon:// URL and reads the result file it
-- writes. A run borrows an empty slot for throwaway TextEdit documents and puts the owner's
-- slots and anchor back afterward, even when it fails halfway or Hammerspoon quits during it.

local keepalive = require("keepalive")
local updates = require("updates")

local T = {}

-- bundle is the app the run makes its throwaway windows in.
T.bundle = "com.apple.TextEdit"

-- event names the hammerspoon:// URL that starts a run.
T.event = "moorings-selftest"

-- landSeconds is how long a window may take to reach the place a check expects.
T.landSeconds = 3

-- holdSeconds is how long a window must stay put for a check that expects it left alone.
T.holdSeconds = 1.5

-- graceSeconds outlasts the time moorings lets a pin settle before a move counts as the owner's.
T.graceSeconds = 2.5

-- openSeconds is how long TextEdit may take to show a new document, including its launch.
T.openSeconds = 10

-- stepSeconds is how often a wait looks again.
T.stepSeconds = 0.1

-- controlShift is how far right the negative control moves the frame its check expects.
T.controlShift = 40

-- planted names the check the negative control makes fail.
T.planted = "anchored window lands in its slot"

-- layoutKey names the setting that holds the owner's layout while a run borrows a slot.
T.layoutKey = "moorings.selftestLayout"

local host
local running = false

-- logDir returns the folder results are written to.
function T.logDir()
  return os.getenv("HOME") .. "/Library/Logs/moorings"
end

-- after calls fn once seconds have passed. Tests replace it.
function T.after(seconds, fn)
  -- pending keeps the timer referenced so it is not collected before it fires.
  T.pending = hs.timer.doAfter(seconds, fn)
end

-- launch starts TextEdit in the background with an untitled document and returns without
-- waiting for it. The argument holds only for this launch and skips the Open panel TextEdit
-- shows at launch, which keystrokes cannot reach. Tests replace it.
function T.launch()
  -- launcher keeps the task referenced so it is not collected while it runs.
  T.launcher = hs.task.new("/usr/bin/open", nil,
    { "-g", "-b", T.bundle, "--args", "-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO" })
  T.launcher:start()
end

-- store saves the owner's layout so a run that dies halfway is undone at the next start.
-- Tests replace it.
function T.store(saved)
  hs.settings.set(T.layoutKey, saved)
end

-- stored returns the layout a run saved and did not forget, or nil. Tests replace it.
function T.stored()
  return hs.settings.get(T.layoutKey)
end

-- forget drops the saved layout once it is back in place. Tests replace it.
function T.forget()
  hs.settings.clear(T.layoutKey)
end

-- app returns the running TextEdit, or nil. Tests replace it.
function T.app()
  return hs.application.applicationsForBundleID(T.bundle)[1]
end

-- openPanel reports whether win is an open panel. Tests replace it.
function T.openPanel(win)
  local ok, ident = pcall(function()
    return hs.axuielement.windowElement(win):attributeValue("AXIdentifier")
  end)
  return ok and ident == "open-panel"
end

-- click clicks the left mouse button at point p and puts the pointer back a moment later.
-- moorings reads the pointer when its mouse tap sees the click, which is only after this
-- returns, so moving the pointer back at once would make the click land somewhere else. Tests
-- replace it.
function T.click(p)
  local back = hs.mouse.absolutePosition()
  hs.eventtap.leftClick(p)
  -- pointerTimer keeps the timer referenced so it is not collected before it fires.
  T.pointerTimer = hs.timer.doAfter(0.5, function() hs.mouse.absolutePosition(back) end)
end

-- key presses key with mods in app, or in the focused window when app is nil. Tests replace
-- it.
function T.key(mods, key, app)
  hs.eventtap.keyStroke(mods, key, 0, app)
end

-- focused returns the focused window, or nil. Tests replace it.
function T.focused()
  return hs.window.focusedWindow()
end

-- frontAt returns the front-most window holding point p, or nil, so a click is sent only
-- where it lands on a window the run made. Tests replace it.
function T.frontAt(p)
  for _, w in ipairs(hs.window.orderedWindows()) do
    local f = w:frame()
    if p.x >= f.x and p.x < f.x + f.w and p.y >= f.y and p.y < f.y + f.h then
      return w
    end
  end
  return nil
end

-- write saves text at path through a temporary file, so a reader never sees half of it. It
-- returns nil and a reason on failure. Tests replace it.
function T.write(path, text)
  hs.fs.mkdir(T.logDir())
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then
    return nil, err
  end
  f:write(text)
  f:close()
  return os.rename(tmp, path)
end

-- resume continues coroutine co and logs an error that escaped it.
local function resume(co)
  local ok, err = coroutine.resume(co)
  if not ok then
    running = false
    host.log("selftest stopped: " .. tostring(err))
  end
end

-- sleep pauses the run for seconds.
local function sleep(seconds)
  local co = coroutine.running()
  T.after(seconds, function() resume(co) end)
  coroutine.yield()
end

-- settled polls fn, which returns whether a check holds and what it saw, until it holds or
-- seconds pass, and returns its last answer.
local function settled(fn, seconds)
  local deadline = host.now() + seconds
  while true do
    local ok, detail = fn()
    if ok or host.now() >= deadline then
      return ok, detail
    end
    sleep(T.stepSeconds)
  end
end

-- steady polls fn for seconds and returns its first failing answer, or its last one.
local function steady(fn, seconds)
  local deadline = host.now() + seconds
  while true do
    local ok, detail = fn()
    if not ok or host.now() >= deadline then
      return ok, detail
    end
    sleep(T.stepSeconds)
  end
end

-- check records the check called name, which passed when ok, with detail saying what was seen.
local function check(run, name, ok, detail)
  run.checks[#run.checks + 1] = { name = name, ok = ok == true, detail = ok and "" or detail or "" }
end

-- skip records the check called name as not run, and why.
local function skip(run, name, why)
  run.checks[#run.checks + 1] = { name = name, ok = true, skipped = true, detail = why }
end

-- show formats frame f for a detail.
local function show(f)
  if not f then
    return "nothing"
  end
  return string.format("{%.0f,%.0f,%.0f,%.0f}", f.x, f.y, f.w, f.h)
end

-- windowsOf returns TextEdit's open panels when panels is true, and its other windows when not.
local function windowsOf(panels)
  local app, list = T.app(), {}
  if not app then
    return list
  end
  for _, w in ipairs(app:allWindows()) do
    if T.openPanel(w) == panels then
      list[#list + 1] = w
    end
  end
  return list
end

-- shown reports whether win is still one of TextEdit's windows.
local function shown(win)
  for _, w in ipairs(windowsOf(false)) do
    if w:id() == win:id() then
      return true
    end
  end
  return false
end

-- landed reports whether win is pinned at the frame moorings gave it, plus shift points to
-- the right, against its screen edge.
local function landed(run, win, shift)
  if not host.pinned(win) then
    return false, "not anchored, at " .. show(win:frame())
  end
  local target = host.target(win)
  if not target then
    return false, "anchored but never placed"
  end
  local want = { x = target.x + (shift or 0), y = target.y, w = target.w, h = target.h }
  local f, s, t = win:frame(), run.screen:frame(), host.config.tolerance
  local edge = math.abs(f.x - s.x) <= t
  if run.side == "right" then
    edge = math.abs(f.x + f.w - s.x - s.w) <= t
  end
  if host.near(f, want) and edge then
    return true
  end
  return false,
    "at " .. show(f) .. ", want " .. show(want) .. " against the " .. run.side .. " edge"
end

-- inChannel reports whether win is free and inside the channel.
local function inChannel(run, win)
  if host.pinned(win) then
    return false, "anchored, at " .. show(win:frame())
  end
  local f, ch, t = win:frame(), host.channel(run.screen), host.config.tolerance
  if f.x >= ch.x - t and f.y >= ch.y - t and f.x + f.w <= ch.x + ch.w + t
    and f.y + f.h <= ch.y + ch.h + t then
    return true
  end
  return false, "at " .. show(f) .. ", channel " .. show(ch)
end

-- at reports whether win still sits at frame f.
local function at(win, f)
  local got = win:frame()
  if host.near(got, f) then
    return true
  end
  return false, "moved to " .. show(got) .. " from " .. show(f)
end

-- dismissPanels closes any open panel TextEdit shows. The panel's contents belong to a system
-- service, so Escape goes to the focused window, and only once that window is the panel.
local function dismissPanels()
  for _, p in ipairs(windowsOf(true)) do
    p:focus()
    if not settled(function()
      local f = T.focused()
      return f ~= nil and f:id() == p:id()
    end, T.landSeconds) then
      error("the TextEdit open panel would not take focus", 0)
    end
    T.key({}, "escape")
  end
  if not settled(function() return #windowsOf(true) == 0 end, T.landSeconds) then
    error("the TextEdit open panel would not close", 0)
  end
end

-- newDocument makes a throwaway TextEdit document and returns its window once it shows. It
-- launches TextEdit when it is not running, and presses Cmd-N in it when it is.
local function newDocument(run)
  local before = {}
  for _, w in ipairs(windowsOf(false)) do
    before[w:id()] = true
  end
  local app = T.app()
  if app then
    app:activate()
    T.key({ "cmd" }, "n", app)
  else
    T.launch()
  end
  local found
  settled(function()
    for _, w in ipairs(windowsOf(false)) do
      if not before[w:id()] and w:isStandard() then
        found = w
        return true
      end
    end
    return false
  end, T.openSeconds)
  if not found then
    error("the new TextEdit document did not show", 0)
  end
  run.made[#run.made + 1] = found
  return found
end

-- close closes win and waits for it to go.
local function close(win)
  win:close()
  if not settled(function() return not shown(win) end, T.landSeconds) then
    error("a TextEdit document would not close", 0)
  end
end

-- prepare checks a run can start and picks the slot TextEdit borrows, preferring one on a
-- side with no other app. It returns nil and a reason when the run cannot start.
local function prepare(run)
  if not hs.accessibilityState() then
    return nil, "Accessibility is not granted"
  end
  run.screen = host.ultrawide()
  if not run.screen then
    return nil, "no ultrawide screen is attached"
  end
  if T.app() then
    return nil, "TextEdit is open. Quit it first, since the run makes throwaway documents in it"
  end
  local picks = host.assignments()
  for _, bundle in pairs(picks) do
    if bundle == T.bundle then
      return nil, "TextEdit is anchored. Take it out of Anchored apps first"
    end
  end
  for _, wantEmptySide in ipairs({ true, false }) do
    for _, s in ipairs(host.slotNames) do
      local other = s.side .. "-" .. (s.row == "top" and "bottom" or "top")
      if picks[s.key] == "" and (picks[other] == "" or not wantEmptySide) then
        run.slot, run.side, run.emptySide = s.key, s.side, wantEmptySide
        return true
      end
    end
  end
  return nil, "every slot is taken. Empty one in Anchored apps first"
end

-- keepAliveCheck checks the restart helper is loaded and matches this version.
local function keepAliveCheck(run)
  local name = "restart helper is loaded and current"
  if not host.keepAlive() then
    skip(run, name, "Restart if it stops is off")
    return
  end
  if keepalive.readFile(keepalive.plistPath()) ~= keepalive.plist(host.path("anchors.lua")) then
    check(run, name, false, keepalive.plistPath() .. " differs from what this version writes")
    return
  end
  check(run, name, keepalive.loaded(), "launchd does not have " .. keepalive.label)
end

-- scenarios runs every check in order, each on throwaway TextEdit windows.
local function scenarios(run)
  host.setPaused(false)
  host.assign(run.slot, T.bundle)
  local a = newDocument(run)
  dismissPanels()
  local shift = run.control and T.controlShift or 0
  check(run, T.planted, settled(function() return landed(run, a, shift) end, T.landSeconds))

  local b = newDocument(run)
  check(run, "second window stays free in the channel",
    settled(function() return inChannel(run, b) end, T.landSeconds))

  close(a)
  check(run, "next window takes the slot when the anchored one closes",
    settled(function() return landed(run, b) end, T.landSeconds))

  close(b)
  local freed = "an anchored app with no window frees its side"
  if run.emptySide then
    check(run, freed, settled(function()
      local left, right = host.inUse(run.screen:frame())
      local pct = run.side == "left" and left or right
      return pct == 0, string.format("the %s side is still %.0f%% wide", run.side, pct)
    end, T.landSeconds))
  else
    skip(run, freed, "another app shares the " .. run.side .. " side")
  end

  local app = T.app()
  app:activate()
  T.key({ "cmd" }, "o", app)
  local panel
  local picker = "open picker is not held"
  if settled(function()
    panel = windowsOf(true)[1]
    return panel ~= nil
  end, T.openSeconds) then
    check(run, picker, steady(function()
      return not host.pinned(panel), "anchored, at " .. show(panel:frame())
    end, T.holdSeconds))
    dismissPanels()
  else
    check(run, picker, false, "the open picker did not show")
  end

  local c = newDocument(run)
  check(run, "a new document takes the slot back",
    settled(function() return landed(run, c) end, T.landSeconds))

  sleep(T.graceSeconds)
  local ch, f = host.channel(run.screen), c:frame()
  c:setFrame({ x = ch.x + 40, y = ch.y + 40, w = math.min(f.w, ch.w - 80), h = f.h })
  local moved = c:frame()
  check(run, "moving the anchored window releases it", settled(function()
    return host.released(c), "not released, at " .. show(c:frame())
  end, T.landSeconds))
  check(run, "a released window stays where it was put",
    steady(function() return at(c, moved) end, T.holdSeconds))

  c:focus()
  local button
  local green = "green button puts a released window back"
  if settled(function()
    local r = c:zoomButtonRect()
    button = { x = r.x + r.w / 2, y = r.y + r.h / 2 }
    local w = T.frontAt(button)
    return w ~= nil and w:id() == c:id()
  end, T.landSeconds) then
    T.click(button)
    check(run, green, settled(function() return landed(run, c) end, T.landSeconds))
  else
    check(run, green, false, "another window covers its green button, so it was not clicked")
  end

  host.setPaused(true)
  c:setFrame(moved)
  moved = c:frame()
  check(run, "weigh anchor leaves windows where they are",
    steady(function() return at(c, moved) end, T.holdSeconds))
  host.setPaused(false)
  check(run, "drop anchor puts the window back",
    settled(function() return landed(run, c) end, T.landSeconds))

  keepAliveCheck(run)
end

-- quitTextEdit quits TextEdit and waits for it to go, forcing it when it ignores the request.
-- Forcing is safe since a run starts only while TextEdit is not open, so every window it has
-- is one the run made.
local function quitTextEdit()
  local app = T.app()
  if not app then
    return
  end
  app:kill()
  if settled(function() return T.app() == nil end, T.landSeconds) then
    return
  end
  app:kill9()
  if not settled(function() return T.app() == nil end, T.landSeconds) then
    error("TextEdit would not quit", 0)
  end
end

-- cleanup closes the windows the run made, puts back the owner's slots and anchor, and quits
-- TextEdit.
local function cleanup(run, saved)
  for _, w in ipairs(run.made) do
    pcall(function() w:close() end)
  end
  host.restoreLayout(saved)
  T.forget()
  quitTextEdit()
end

-- finish writes the result of run, which stopped with err when err is set.
local function finish(run, err)
  local pass = err == nil
  local failed = 0
  for _, c in ipairs(run.checks) do
    if not c.ok then
      pass, failed = false, failed + 1
    end
  end
  local result = {
    run = run.id, version = updates.version, pass = pass, error = err, checks = run.checks,
    planted = run.control and T.planted or nil,
  }
  local path = T.logDir() .. "/selftest-" .. run.id .. ".json"
  local ok, werr = T.write(path, hs.json.encode(result, true))
  if not ok then
    host.log("selftest result not written: " .. tostring(werr))
  end
  host.log(string.format("selftest %s: %d checks, %d failed%s", run.id, #run.checks, failed,
    err and (", stopped: " .. err) or ""))
end

-- start runs a selftest named id, planting one failure when control is true, unless a run is
-- going. The run begins on a timer, so the URL handler that asked for it returns first. It
-- reports whether the run started.
function T.start(id, control)
  if running then
    host.log("selftest " .. id .. " not started: another run is going")
    return false
  end
  running = true
  local run = { id = id, control = control == true, checks = {}, made = {} }
  local co = coroutine.create(function()
    local ok, err = prepare(run)
    if ok then
      local saved = host.snapshotLayout()
      T.store(saved)
      ok, err = pcall(scenarios, run)
      local cleaned, cerr = pcall(cleanup, run, saved)
      if ok and not cleaned then
        ok, err = false, cerr
      end
    end
    finish(run, not ok and tostring(err) or nil)
    running = false
  end)
  T.after(0, function() resume(co) end)
  return true
end

-- recover puts back a layout a run saved and never restored, because Hammerspoon quit or
-- reloaded during it.
local function recover()
  local saved = T.stored()
  if not saved then
    return
  end
  local ok, err = pcall(host.restoreLayout, saved)
  T.forget()
  if ok then
    host.log("selftest: put back the layout a stopped run left")
  else
    host.log("selftest: could not put back the layout a stopped run left: " .. tostring(err))
  end
end

-- attach keeps host, the anchors module, puts back a layout a stopped run left, and binds the
-- URL that starts a run. The URL names the run with letters, digits and hyphens, and control=1
-- plants the negative control.
function T.attach(h)
  host = h
  recover()
  hs.urlevent.bind(T.event, host.safe(function(_, params)
    local id = params and params.run
    if type(id) ~= "string" or #id > 64 or not id:match("^[%w%-]+$") then
      host.log("selftest not started: the URL needs run=<letters, digits and hyphens>")
      return
    end
    T.start(id, params.control == "1")
  end))
end

return T
