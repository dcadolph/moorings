-- updates_test drives updates.lua against a fake Hammerspoon with no network. Run it from the
-- repo root with: lua tests/updates_test.lua

package.path = "./?.lua;" .. package.path

local failures, passes = 0, 0
local world, U

-- check records a failure when cond is false.
local function check(name, cond, msg)
  if cond then
    passes = passes + 1
  else
    failures = failures + 1
    print("FAIL " .. name .. ": " .. (msg or "condition false"))
  end
end

-- install loads a fresh updates module into a fake world. hsVersion is Hammerspoon's version.
local function install(hsVersion)
  world = {
    settings = {}, gets = {}, tasks = {}, logs = {}, notices = {}, urls = {}, clock = 1000000,
    paths = {}, attrs = {}, reloads = 0, timers = {},
  }
  hs = {
    configdir = "/Users/me/.hammerspoon",
    processInfo = { version = hsVersion or "1.1.1" },
    settings = {
      get = function(k) return world.settings[k] end,
      set = function(k, v) world.settings[k] = v end,
    },
    http = {
      asyncGet = function(url, headers, fn)
        world.gets[#world.gets + 1] = { url = url, headers = headers, fn = fn }
      end,
    },
    json = {
      decode = function(body)
        local tag = body:match('"tag_name"%s*:%s*"([^"]*)"')
        if not tag then error("bad json") end
        return { tag_name = tag }
      end,
    },
    fs = {
      pathToAbsolute = function(p) return world.paths[p] end,
      attributes = function(p) return world.attrs[p] end,
    },
    task = {
      new = function(path, fn, args)
        local t = { path = path, fn = fn, args = args }
        function t:start() self.started = true return self end
        world.tasks[#world.tasks + 1] = t
        return t
      end,
    },
    urlevent = { openURL = function(u) world.urls[#world.urls + 1] = u end },
    timer = {
      doAfter = function(s, fn)
        world.timers[#world.timers + 1] = { after = s, fn = fn }
        return {}
      end,
      doEvery = function(s, fn)
        world.timers[#world.timers + 1] = { every = s, fn = fn }
        return {}
      end,
    },
    checkForUpdates = function() world.hsChecked = true end,
  }
  package.loaded.updates = nil
  U = require("updates")
  U.attach({
    now = function() return world.clock end,
    log = function(m) world.logs[#world.logs + 1] = m end,
    notify = function(t, x) world.notices[#world.notices + 1] = { title = t, text = x } end,
    reload = function() world.reloads = world.reloads + 1 end,
    safe = function(fn) return fn end,
  })
end

-- answer completes the oldest pending GitHub request with status and body.
local function answer(status, body)
  local g = table.remove(world.gets, 1)
  g.fn(status, body, {})
end

-- titles joins the titles of items.
local function titles(items)
  local out = {}
  for i, it in ipairs(items) do out[i] = it.title end
  return table.concat(out, ",")
end

local tests = {}

-- Test 0: Versions parse with or without v, and anything else, prereleases included, does not.
tests[#tests + 1] = function()
  install()
  local p = U.parse("v1.20.3")
  check("t0 v", p and p[1] == 1 and p[2] == 20 and p[3] == 3)
  check("t0 bare", U.parse("2.0.0") ~= nil)
  for _, bad in ipairs({ "v1.2", "v1.2.3-rc1", "1.2.3 ", "x1.2.3", "", "latest" }) do
    check("t0 rejects " .. bad, U.parse(bad) == nil)
  end
  check("t0 nil", U.parse(nil) == nil and U.parse(5) == nil)
end

-- Test 1: newer compares numbers, not text, part by part, and never calls a bad version newer.
tests[#tests + 1] = function()
  install()
  check("t1 patch", U.newer("v1.0.10", "1.0.9"))
  check("t1 minor", U.newer("v1.10.0", "v1.9.99"))
  check("t1 major", U.newer("v2.0.0", "v1.99.99"))
  check("t1 equal", not U.newer("v1.1.0", "1.1.0"))
  check("t1 older", not U.newer("v1.0.9", "v1.1.0"))
  check("t1 bad", not U.newer("v9.0.0-rc1", "v1.0.0") and not U.newer("v1.0.0", nil))
end

-- Test 2: Start waits a minute for the first check, wakes hourly, and a due wake asks GitHub
-- for the latest release with the API and agent headers.
tests[#tests + 1] = function()
  install()
  check("t2 timers", #world.timers == 2 and world.timers[1].after == 60
    and world.timers[2].every == 3600)
  check("t2 nothing yet", #world.gets == 0)
  world.timers[1].fn()
  check("t2 asked", #world.gets == 1
    and world.gets[1].url == "https://api.github.com/repos/dcadolph/moorings/releases/latest")
  check("t2 headers", world.gets[1].headers.Accept == "application/vnd.github+json"
    and world.gets[1].headers["User-Agent"] == "moorings/" .. U.version)
  answer(200, '{"tag_name": "v0.1.0"}')
  install()
  world.settings["moorings.updateCheckedAt"] = world.clock - 3600
  world.timers[1].fn()
  world.timers[2].fn()
  check("t2 reload inside a day asks nothing", #world.gets == 0)
end

-- Test 3: A newer release is remembered and offered first, a check inside a day does not ask
-- again, and a day later it does.
tests[#tests + 1] = function()
  install()
  U.wake()
  answer(200, '{"tag_name": "v9.1.0"}')
  check("t3 latest", U.latest() == "v9.1.0")
  check("t3 kept", world.settings["moorings.latestRelease"] == "v9.1.0"
    and world.settings["moorings.updateCheckedAt"] == world.clock)
  local items = U.menuItems()
  check("t3 item", titles(items) == "Update moorings (v9.1.0)", titles(items))
  check("t3 hint", items[1].tooltip:find("You have v" .. U.version, 1, true) ~= nil)
  world.clock = world.clock + 23 * 3600
  U.wake()
  check("t3 fresh", #world.gets == 0)
  world.clock = world.clock + 3600
  U.wake()
  check("t3 stale", #world.gets == 1)
end

-- Test 4: A release equal to or older than this one shows nothing.
tests[#tests + 1] = function()
  install()
  U.wake()
  answer(200, '{"tag_name": "v' .. U.version .. '"}')
  check("t4 equal", U.latest() == nil and #U.menuItems() == 0)
  U.check()
  answer(200, '{"tag_name": "v0.9.0"}')
  check("t4 older", U.latest() == nil and #U.menuItems() == 0)
end

-- Test 5: Failures stay quiet: a bad status, a body that does not decode, and a tag that is
-- not a version each log one line, keep the last good answer, and leave the clock alone so the
-- next wake tries again.
tests[#tests + 1] = function()
  install()
  world.settings["moorings.latestRelease"] = "v9.0.0"
  for i, case in ipairs({ { 403, "rate limited" }, { 200, "<html>" }, { 200, '{"tag_name": "nightly"}' },
    { -1, nil } }) do
    U.check()
    answer(case[1], case[2])
    check("t5 logged " .. i, #world.logs == i, tostring(#world.logs))
  end
  check("t5 kept", U.latest() == "v9.0.0")
  check("t5 no clock", world.settings["moorings.updateCheckedAt"] == nil)
  check("t5 no banner", #world.notices == 0)
  check("t5 status logged", world.logs[1]:find("403", 1, true) ~= nil, world.logs[1])
  U.wake()
  check("t5 retries", #world.gets == 1)
end

-- Test 6: Turned off, no check runs and a known update is hidden. Turned on, it checks at once.
tests[#tests + 1] = function()
  install()
  world.settings["moorings.latestRelease"] = "v9.0.0"
  local toggle = U.settingItems()[1]
  check("t6 on by default", U.on() and toggle.checked == true)
  toggle.fn()
  check("t6 off", world.settings["moorings.updateChecks"] == false and U.settingItems()[1].checked == false)
  check("t6 hidden", U.latest() == nil and #U.menuItems() == 0)
  U.wake()
  check("t6 no check", #world.gets == 0)
  U.settingItems()[1].fn()
  check("t6 on checks", U.on() and #world.gets == 1)
end

-- Test 7: Check now reports each outcome in a banner.
tests[#tests + 1] = function()
  install()
  local now = U.settingItems()[2]
  check("t7 title", now.title == "Check for updates now")
  now.fn()
  answer(200, '{"tag_name": "v' .. U.version .. '"}')
  check("t7 current", world.notices[1].title == "moorings is up to date"
    and world.notices[1].text == "You have v" .. U.version .. ".")
  now.fn()
  answer(200, '{"tag_name": "v9.0.0"}')
  check("t7 newer", world.notices[2].title == "moorings v9.0.0 is out")
  now.fn()
  answer(500, "")
  check("t7 failed", world.notices[3].title == "Update check failed"
    and world.notices[3].text:find("500", 1, true) ~= nil, world.notices[3].text)
end

-- Test 8: The install source comes from the folder's real path: a Cellar path is Homebrew with
-- the brew next to it, a folder with .git is a clone, and anything else is a download.
tests[#tests + 1] = function()
  install()
  world.paths["/x"] = "/opt/homebrew/Cellar/moorings/1.1.0/share/moorings"
  local kind, where = U.source("/x")
  check("t8 brew arm", kind == "brew" and where == "/opt/homebrew/bin/brew", tostring(where))
  world.paths["/x"] = "/usr/local/Cellar/moorings/1.1.0/share/moorings"
  kind, where = U.source("/x")
  check("t8 brew intel", kind == "brew" and where == "/usr/local/bin/brew", tostring(where))
  world.paths["/x"] = "/Users/me/Cellar/notes/moorings"
  world.attrs["/Users/me/Cellar/notes/moorings/.git"] = { mode = "directory" }
  check("t8 other Cellar", U.source("/x") == "git")
  world.paths["/x"] = "/Users/me/src/moorings"
  world.attrs["/Users/me/src/moorings/.git"] = { mode = "directory" }
  kind, where = U.source("/x")
  check("t8 git", kind == "git" and where == "/Users/me/src/moorings")
  world.paths["/x"] = "/Users/me/Downloads/moorings-1.1.0"
  kind = U.source("/x")
  check("t8 download", kind == "download")
  world.paths["/x"] = nil
  kind, where = U.source("/x")
  check("t8 unresolved", kind == "download" and where == "/x")
end

-- Test 9: The update commands quote their paths, and git only fast-forwards.
tests[#tests + 1] = function()
  install()
  check("t9 brew", U.command("brew", "/opt/home brew/bin/brew")
    == "'/opt/home brew/bin/brew' update --quiet && '/opt/home brew/bin/brew' upgrade moorings")
  check("t9 git", U.command("git", "/Users/me/it's") == "/usr/bin/git -C '/Users/me/it'\\''s' pull --ff-only",
    U.command("git", "/Users/me/it's"))
end

-- Test 10: Clicking the update runs the command for the install, shows Updating while it runs,
-- and reloads only when it succeeds. A failure logs the output and shows a banner.
tests[#tests + 1] = function()
  install()
  world.settings["moorings.latestRelease"] = "v9.0.0"
  world.paths["/Users/me/.hammerspoon/moorings"] = "/opt/homebrew/Cellar/moorings/1.1.0/share/moorings"
  U.menuItems()[1].fn()
  local t = world.tasks[1]
  check("t10 task", t and t.started and t.path == "/bin/sh" and t.args[1] == "-c"
    and t.args[2] == U.command("brew", "/opt/homebrew/bin/brew"))
  local items = U.menuItems()
  check("t10 running", titles(items) == "Updating moorings…" and items[1].disabled == true)
  t.fn(1, "Error: no such formula", "")
  check("t10 no reload", world.reloads == 0)
  check("t10 failed", world.notices[1].title == "moorings did not update"
    and world.logs[1]:find("no such formula", 1, true) ~= nil)
  check("t10 offered again", titles(U.menuItems()) == "Update moorings (v9.0.0)")
  U.menuItems()[1].fn()
  world.tasks[2].fn(0, "", "")
  check("t10 reloaded", world.reloads == 1)
end

-- Test 11: A git install pulls, and a download install opens the release page and runs nothing.
tests[#tests + 1] = function()
  install()
  world.settings["moorings.latestRelease"] = "v9.0.0"
  world.paths["/Users/me/.hammerspoon/moorings"] = "/Users/me/src/moorings"
  world.attrs["/Users/me/src/moorings/.git"] = { mode = "directory" }
  U.install()
  check("t11 git", world.tasks[1].args[2] == "/usr/bin/git -C '/Users/me/src/moorings' pull --ff-only")
  install()
  world.paths["/Users/me/.hammerspoon/moorings"] = "/Users/me/Downloads/moorings"
  U.install()
  check("t11 download", #world.tasks == 0 and world.urls[1] == U.page)
end

-- Test 12: An older Hammerspoon logs once at start and shows an entry that checks for a
-- Hammerspoon update. The tested version and newer ones show nothing.
tests[#tests + 1] = function()
  install("1.0.0")
  check("t12 logged", #world.logs == 1 and world.logs[1]:find("1.0.0", 1, true) ~= nil)
  local items = U.menuItems()
  check("t12 item", titles(items) == "Hammerspoon 1.0.0 is older than moorings needs ("
    .. U.minHammerspoon .. ")", titles(items))
  items[1].fn()
  check("t12 checks", world.hsChecked == true)
  install(U.minHammerspoon)
  check("t12 tested", #world.logs == 0 and #U.menuItems() == 0)
  install("2.0.0")
  check("t12 newer", #U.menuItems() == 0)
  install()
  hs.processInfo.version = nil
  check("t12 unknown", U.hammerspoonOld() == nil)
end

-- Test 13: Every entry has a hover hint.
tests[#tests + 1] = function()
  install("1.0.0")
  world.settings["moorings.latestRelease"] = "v9.0.0"
  local all = U.menuItems()
  for _, it in ipairs(U.settingItems()) do all[#all + 1] = it end
  for _, it in ipairs(all) do
    check("t13 " .. it.title, type(it.tooltip) == "string" and #it.tooltip > 0)
  end
  check("t13 count", #all == 4)
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
