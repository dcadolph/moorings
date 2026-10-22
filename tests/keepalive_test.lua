-- keepalive_test drives keepalive.lua against a fake shell and file system. Run it from the
-- repo root with: lua tests/keepalive_test.lua

package.path = "./?.lua;" .. package.path

local failures, passes = 0, 0
local world, K

-- sentinel is the file whose presence means moorings is installed.
local sentinel = "/Users/me/.hammerspoon/moorings/anchors.lua"

-- check records a failure when cond is false.
local function check(name, cond, msg)
  if cond then
    passes = passes + 1
  else
    failures = failures + 1
    print("FAIL " .. name .. ": " .. (msg or "condition false"))
  end
end

-- has reports whether s contains plain text.
local function has(s, text)
  return s ~= nil and s:find(text, 1, true) ~= nil
end

-- ran returns the commands run that contain text.
local function ran(text)
  local list = {}
  for _, cmd in ipairs(world.commands) do
    if has(cmd, text) then list[#list + 1] = cmd end
  end
  return list
end

-- install loads a fresh keepalive into a fake world where launchd has the agent when loaded
-- is set.
local function install()
  world = { commands = {}, files = {}, env = {}, loaded = false, bootstrapOK = true, writes = 0 }
  hs = { execute = function() error("keepalive ran a real shell command") end }
  package.loaded.keepalive = nil
  K = require("keepalive")
  K.home = "/Users/me"
  K.getenv = function(name) return world.env[name] end
  K.run = function(cmd)
    world.commands[#world.commands + 1] = cmd
    if has(cmd, "launchctl print") then
      return "", world.loaded
    end
    if has(cmd, "launchctl bootstrap") then
      if not world.bootstrapOK then
        return "Bootstrap failed: 5: Input/output error", false
      end
      world.loaded = true
      return "", true
    end
    if has(cmd, "launchctl bootout") then
      local was = world.loaded
      world.loaded = false
      return "", was
    end
    return "", true
  end
  K.readFile = function(path) return world.files[path] end
  K.writeFile = function(path, text)
    if world.writeFails then return nil, "Permission denied" end
    world.writes = world.writes + 1
    world.files[path] = text
    return true
  end
  K.deleteFile = function(path) world.files[path] = nil end
end

local tests = {}

-- Test 0: The plist names the agent, lists it under Hammerspoon, runs every 30 seconds and
-- not at load, and lives in the user's LaunchAgents folder.
tests[#tests + 1] = function()
  install()
  local p = K.plist(sentinel)
  check("t0 path", K.plistPath() == "/Users/me/Library/LaunchAgents/moorings.keepalive.plist",
    K.plistPath())
  check("t0 label", has(p, "<key>Label</key>\n\t<string>moorings.keepalive</string>"))
  check("t0 listed as Hammerspoon", has(p, "<key>AssociatedBundleIdentifiers</key>\n\t<array>\n"
    .. "\t\t<string>org.hammerspoon.Hammerspoon</string>"))
  check("t0 interval", has(p, "<key>StartInterval</key>\n\t<integer>30</integer>"))
  check("t0 not at load", has(p, "<key>RunAtLoad</key>\n\t<false/>"))
  check("t0 shell", has(p, "<string>/bin/sh</string>\n\t\t<string>-c</string>"))
  check("t0 background", has(p, "<key>ProcessType</key>\n\t<string>Background</string>"))
  check("t0 ends with newline", p:sub(-9) == "</plist>\n")
end

-- Test 1: The agent's command stops once moorings is gone, checks this user's Hammerspoon by
-- exact name, and opens it in the background by bundle ID, marked as revived.
tests[#tests + 1] = function()
  install()
  local c = K.command(sentinel)
  check("t1 command", c == "[ -e '" .. sentinel .. "' ] || exit 0; "
    .. "/usr/bin/pgrep -xq -U \"$(/usr/bin/id -u)\" Hammerspoon || "
    .. "/usr/bin/open -g --env MOORINGS_REVIVED=1 -b org.hammerspoon.Hammerspoon", c)
end

-- Test 2: A sentinel path with a quote, an ampersand and angle brackets is quoted for the shell
-- and escaped for XML.
tests[#tests + 1] = function()
  install()
  local odd = "/Users/me/Tom's <a&b>/anchors.lua"
  check("t2 shell quote", has(K.command(odd), [['/Users/me/Tom'\''s <a&b>/anchors.lua']]))
  local p = K.plist(odd)
  check("t2 xml escape", has(p, [[Tom'\''s &lt;a&amp;b&gt;/anchors.lua]]))
  check("t2 no raw ampersand", not has(p, "<a&b>"))
end

-- Test 3: A first install makes the folder, writes the plist and loads it into the user's
-- launchd domain.
tests[#tests + 1] = function()
  install()
  local ok, err = K.install(sentinel)
  check("t3 ok", ok == true and err == nil, tostring(err))
  check("t3 written", world.files[K.plistPath()] == K.plist(sentinel))
  check("t3 folder", #ran("/bin/mkdir -p '/Users/me/Library/LaunchAgents'") == 1)
  local boot = ran("launchctl bootstrap")
  check("t3 bootstrap", #boot == 1 and boot[1] == "/bin/launchctl bootstrap gui/$(/usr/bin/id -u) "
    .. "'/Users/me/Library/LaunchAgents/moorings.keepalive.plist' 2>&1", boot[1])
  check("t3 loaded", world.loaded)
end

-- Test 4: An install over the same plist with the agent loaded only asks launchd, so a Reload
-- writes nothing and reloads nothing.
tests[#tests + 1] = function()
  install()
  K.install(sentinel)
  world.commands, world.writes = {}, 0
  local ok = K.install(sentinel)
  check("t4 ok", ok == true)
  check("t4 one command", #world.commands == 1
    and world.commands[1] == "/bin/launchctl print gui/$(/usr/bin/id -u)/moorings.keepalive "
    .. ">/dev/null 2>&1", table.concat(world.commands, " | "))
  check("t4 no write", world.writes == 0)
end

-- Test 5: The same plist with the agent not loaded, as after a failed bootstrap, is loaded
-- again without a rewrite or a bootout.
tests[#tests + 1] = function()
  install()
  K.install(sentinel)
  world.loaded, world.commands, world.writes = false, {}, 0
  local ok = K.install(sentinel)
  check("t5 ok", ok == true and world.loaded)
  check("t5 no write", world.writes == 0)
  check("t5 no bootout", #ran("bootout") == 0)
  check("t5 bootstrap", #ran("bootstrap") == 1)
end

-- Test 6: A changed plist is rewritten and the old job is booted out before the new one loads.
tests[#tests + 1] = function()
  install()
  K.install(sentinel)
  world.commands, world.writes = {}, 0
  local moved = "/Users/me/elsewhere/moorings/anchors.lua"
  local ok = K.install(moved)
  check("t6 ok", ok == true)
  check("t6 rewritten", world.writes == 1 and world.files[K.plistPath()] == K.plist(moved))
  local out, boot
  for i, cmd in ipairs(world.commands) do
    if has(cmd, "bootout") then out = i end
    if has(cmd, "bootstrap") then boot = i end
  end
  check("t6 bootout first", out ~= nil and boot ~= nil and out < boot,
    table.concat(world.commands, " | "))
  check("t6 bootout target", has(world.commands[out or 1],
    "/bin/launchctl bootout gui/$(/usr/bin/id -u)/moorings.keepalive"))
end

-- Test 7: A plist that cannot be written is reported and nothing is loaded.
tests[#tests + 1] = function()
  install()
  world.writeFails = true
  local ok, err = K.install(sentinel)
  check("t7 failed", ok == nil and err == "keep-alive not written: Permission denied",
    tostring(err))
  check("t7 nothing loaded", #ran("bootstrap") == 0 and not world.loaded)
end

-- Test 8: A bootstrap launchd refuses, as when the owner turned the item off in Login Items,
-- is reported with launchd's words.
tests[#tests + 1] = function()
  install()
  world.bootstrapOK = false
  local ok, err = K.install(sentinel)
  check("t8 failed", ok == nil
    and err == "keep-alive not loaded: Bootstrap failed: 5: Input/output error", tostring(err))
  check("t8 plist kept", world.files[K.plistPath()] ~= nil)
end

-- Test 9: Uninstall boots the agent out and deletes its plist, and does no harm when neither
-- is there.
tests[#tests + 1] = function()
  install()
  K.install(sentinel)
  world.commands = {}
  K.uninstall()
  check("t9 unloaded", not world.loaded and #ran("/bin/launchctl bootout gui/$(/usr/bin/id -u)/"
    .. "moorings.keepalive >/dev/null 2>&1") == 1)
  check("t9 deleted", world.files[K.plistPath()] == nil)
  local ok = pcall(K.uninstall)
  check("t9 again", ok)
end

-- Test 10: Revived reads the variable the agent sets when it opens Hammerspoon.
tests[#tests + 1] = function()
  install()
  check("t10 not revived", K.revived() == false)
  world.env.MOORINGS_REVIVED = "1"
  check("t10 revived", K.revived() == true)
end

-- Test 11: The real file helpers write, read back and delete a file, and the real runner
-- reports the shell's exit status.
tests[#tests + 1] = function()
  package.loaded.keepalive = nil
  local real = require("keepalive")
  local path = os.tmpname()
  check("t11 write", real.writeFile(path, "a\nb\n") == true)
  check("t11 read", real.readFile(path) == "a\nb\n")
  real.deleteFile(path)
  check("t11 deleted", real.readFile(path) == nil)
  local w, err = real.writeFile("/nonexistent-dir/x.plist", "x")
  check("t11 write fails", w == nil and err ~= nil)
  hs = { execute = function(cmd) return cmd, cmd == "good" or nil end }
  local out, ok = real.run("good")
  check("t11 run ok", out == "good" and ok == true)
  local _, bad = real.run("bad")
  check("t11 run fails", bad == false)
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
