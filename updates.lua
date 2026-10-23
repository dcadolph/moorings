-- updates asks GitHub once a day for a newer moorings release, offers it at the top of the
-- menu, and installs it on a click the same way moorings was installed. It also warns when
-- Hammerspoon is older than the version moorings was checked on.

local U = {}

-- version is this moorings release. The release workflow refuses a tag that differs.
U.version = "1.4.0"

-- minHammerspoon is the oldest Hammerspoon moorings has been checked on.
U.minHammerspoon = "1.1.1"

-- api is the GitHub endpoint that names the latest release.
U.api = "https://api.github.com/repos/dcadolph/moorings/releases/latest"

-- page is the release page a click opens when moorings cannot update itself.
U.page = "https://github.com/dcadolph/moorings/releases/latest"

-- everySeconds is how long one check stays fresh.
U.everySeconds = 24 * 60 * 60

-- firstSeconds is how long after start the first check waits, so it never slows a login.
U.firstSeconds = 60

-- wakeSeconds is how often moorings looks at whether a check is due.
U.wakeSeconds = 60 * 60

-- keys are the Hammerspoon settings the checks are kept under, so a Reload keeps them.
local keys = {
  on = "moorings.updateChecks",
  checkedAt = "moorings.updateCheckedAt",
  latest = "moorings.latestRelease",
  updatedFrom = "moorings.updatedFrom",
}

local host
local state = {}

-- parse returns the three numbers of a version such as "v1.2.3", or nil for anything else,
-- prereleases included.
function U.parse(v)
  if type(v) ~= "string" then
    return nil
  end
  local a, b, c = v:match("^v?(%d+)%.(%d+)%.(%d+)$")
  if not a then
    return nil
  end
  return { tonumber(a), tonumber(b), tonumber(c) }
end

-- newer reports whether version a is later than version b. A version that does not parse is
-- never newer and nothing is newer than it.
function U.newer(a, b)
  local x, y = U.parse(a), U.parse(b)
  if not x or not y then
    return false
  end
  for i = 1, 3 do
    if x[i] ~= y[i] then
      return x[i] > y[i]
    end
  end
  return false
end

-- on reports whether moorings checks for updates, which it does unless the owner turned it off.
function U.on()
  return hs.settings.get(keys.on) ~= false
end

-- latest returns the newer release the last check found, or nil when there is none.
function U.latest()
  local tag = hs.settings.get(keys.latest)
  if U.on() and U.newer(tag, U.version) then
    return tag
  end
  return nil
end

-- hammerspoonOld returns Hammerspoon's version when it is older than minHammerspoon.
function U.hammerspoonOld()
  local v = hs.processInfo and hs.processInfo.version
  if U.newer(U.minHammerspoon, v) then
    return v
  end
  return nil
end

-- shellQuote wraps s in single quotes for the shell.
local function shellQuote(s)
  return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

-- source describes how moorings was installed, from the real path of its folder: "brew" with
-- the brew command, "git" with the clone's folder, or "download".
function U.source(dir)
  local real = hs.fs.pathToAbsolute(dir) or dir
  local prefix = real:match("^(.*)/Cellar/moorings/")
  if prefix then
    return "brew", prefix .. "/bin/brew"
  end
  if hs.fs.attributes(real .. "/.git") then
    return "git", real
  end
  return "download", real
end

-- command returns the shell line that updates a brew or git install.
function U.command(kind, where)
  if kind == "brew" then
    return shellQuote(where) .. " update --quiet && " .. shellQuote(where) .. " upgrade moorings"
  end
  return "/usr/bin/git -C " .. shellQuote(where) .. " pull --ff-only"
end

-- record keeps the result of a check that reached GitHub.
local function record(tag)
  hs.settings.set(keys.checkedAt, host.now())
  hs.settings.set(keys.latest, tag)
end

-- check asks GitHub for the latest release and remembers it. done, when given, gets the tag,
-- or nil and a reason when the check failed.
function U.check(done)
  done = done or function() end
  hs.http.asyncGet(U.api, {
    ["Accept"] = "application/vnd.github+json",
    ["User-Agent"] = "moorings/" .. U.version,
  }, function(status, body)
    if status ~= 200 then
      host.log("update check failed: GitHub answered " .. tostring(status))
      done(nil, "GitHub answered " .. tostring(status))
      return
    end
    local ok, data = pcall(hs.json.decode, body or "")
    local tag = ok and type(data) == "table" and data.tag_name or nil
    if not U.parse(tag) then
      host.log("update check failed: no release version in the answer")
      done(nil, "no release version in the answer")
      return
    end
    record(tag)
    done(tag)
  end)
end

-- due reports whether the last check is older than everySeconds.
local function due()
  local at = hs.settings.get(keys.checkedAt)
  return type(at) ~= "number" or host.now() - at >= U.everySeconds
end

-- wake checks for an update when checks are on and the last one is stale.
function U.wake()
  if U.on() and due() then
    U.check()
  end
end

-- setOn turns the daily check on or off. Turned on, it checks right away.
function U.setOn(on)
  hs.settings.set(keys.on, on == true)
  if on then
    U.check()
  end
end

-- checkNow checks at once and shows the result in a banner.
function U.checkNow()
  U.check(function(tag, problem)
    if not tag then
      host.notify("Update check failed", problem .. ". The Console has the details.")
    elseif U.newer(tag, U.version) then
      host.notify("moorings " .. tag .. " is out", "Choose Update moorings at the top of the menu.")
    else
      host.notify("moorings is up to date", "You have v" .. U.version .. ".")
    end
  end)
end

-- install updates moorings the way it was installed and reloads when that worked. Before the
-- reload it remembers the running version and forgets the last check, so the next start can
-- say what changed and ask GitHub again. A download install opens the release page instead.
function U.install()
  local kind, where = U.source(hs.configdir .. "/moorings")
  if kind == "download" then
    hs.urlevent.openURL(U.page)
    return
  end
  state.running = true
  host.notify("Updating moorings…", "moorings reloads when the update finishes.")
  hs.task.new("/bin/sh", function(code, out, err)
    state.running = false
    if code == 0 then
      hs.settings.set(keys.updatedFrom, U.version)
      hs.settings.clear(keys.latest)
      hs.settings.clear(keys.checkedAt)
      host.reload()
      return
    end
    host.log("update failed: " .. tostring(out) .. tostring(err))
    host.notify("moorings did not update", "The Console shows why.")
  end, { "-c", U.command(kind, where) }):start()
end

-- menuItems returns the entries for the top of the menu: an update when one is out and a
-- warning when Hammerspoon is too old.
function U.menuItems()
  local items = {}
  local tag = U.latest()
  if state.running then
    items[#items + 1] = {
      title = "Updating moorings…",
      tooltip = "moorings reloads when the update finishes.",
      disabled = true,
    }
  elseif tag then
    items[#items + 1] = {
      title = "Update moorings (" .. tag .. ")",
      tooltip = "Install " .. tag .. " the way moorings was installed, then reload. "
        .. "You have v" .. U.version .. ".",
      fn = host.safe(U.install),
    }
  end
  local old = U.hammerspoonOld()
  if old then
    items[#items + 1] = {
      title = "Hammerspoon " .. old .. " is older than moorings needs (" .. U.minHammerspoon .. ")",
      tooltip = "Check for a Hammerspoon update.",
      fn = host.safe(function()
        if hs.checkForUpdates then
          hs.checkForUpdates()
        end
      end),
    }
  end
  return items
end

-- settingItems returns the update entries for the Settings folder.
function U.settingItems()
  return {
    {
      title = "Check for moorings updates",
      tooltip = "Once a day, ask GitHub whether a newer moorings is out. Nothing installs "
        .. "until you choose it.",
      checked = U.on(),
      fn = host.safe(function() U.setOn(not U.on()) end),
    },
    {
      title = "Check for updates now",
      tooltip = "Ask GitHub now and show the answer. You have v" .. U.version .. ".",
      fn = host.safe(U.checkNow),
    },
  }
end

-- reportUpdate says how an update that just reloaded moorings turned out. When it brought no
-- newer version it asks GitHub again at once, so the menu shows the real latest release.
local function reportUpdate()
  local from = hs.settings.get(keys.updatedFrom)
  if from == nil then
    return
  end
  hs.settings.clear(keys.updatedFrom)
  if type(from) ~= "string" then
    return
  end
  if U.newer(U.version, from) then
    host.notify("moorings updated to v" .. U.version, "You had v" .. from .. ".")
    return
  end
  host.notify("No newer moorings was installed", "You have v" .. U.version .. ".")
  U.check()
end

-- attach gives updates the anchors module, reports an update that just reloaded it, logs an
-- old Hammerspoon once and starts the timers.
function U.attach(m)
  host = m
  state.running = false
  reportUpdate()
  local old = U.hammerspoonOld()
  if old then
    host.log("Hammerspoon " .. old .. " is older than " .. U.minHammerspoon
      .. ", the oldest moorings was checked on")
  end
  state.first = hs.timer.doAfter(U.firstSeconds, host.safe(U.wake))
  state.timer = hs.timer.doEvery(U.wakeSeconds, host.safe(U.wake))
end

return U
