-- keepalive installs a user LaunchAgent that starts Hammerspoon again within half a minute of
-- it quitting or crashing, so moorings keeps holding the layout.

local K = {}

-- label names the LaunchAgent and its plist file.
K.label = "moorings.keepalive"

-- bundle is Hammerspoon's bundle ID, which the agent opens and names as its associated app.
K.bundle = "org.hammerspoon.Hammerspoon"

-- seconds is how often the agent checks that Hammerspoon is running.
K.seconds = 30

-- revivedVar is set in the environment of a Hammerspoon the agent started.
K.revivedVar = "MOORINGS_REVIVED"

-- home is the user's home folder, which holds Library/LaunchAgents.
K.home = os.getenv("HOME")

-- getenv reads the environment. Tests replace it.
K.getenv = os.getenv

-- run runs cmd through the shell and returns its output and whether it exited zero. Tests
-- replace it.
function K.run(cmd)
  local out, ok = hs.execute(cmd)
  return out, ok == true
end

-- readFile returns the contents of path, or nil when it cannot be read. Tests replace it.
function K.readFile(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("a")
  f:close()
  return text
end

-- writeFile replaces the contents of path with text and returns nil and a reason on failure.
-- Tests replace it.
function K.writeFile(path, text)
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:write(text)
  f:close()
  return true
end

-- deleteFile removes path if it exists. Tests replace it.
function K.deleteFile(path)
  os.remove(path)
end

-- domain is the launchd domain of the logged-in user, resolved by the shell.
local domain = "gui/$(/usr/bin/id -u)"

-- shellQuote wraps s in single quotes for the shell.
local function shellQuote(s)
  return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

-- xmlEscape escapes the characters XML reserves in s.
local function xmlEscape(s)
  return (s:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

-- dir returns the folder that holds the plist.
local function dir()
  return K.home .. "/Library/LaunchAgents"
end

-- plistPath returns the full path of the agent's plist.
function K.plistPath()
  return dir() .. "/" .. K.label .. ".plist"
end

-- command returns the shell line the agent runs. It does nothing once sentinel is gone, so
-- deleting moorings stops the revivals, or while Hammerspoon runs for this user.
function K.command(sentinel)
  return "[ -e " .. shellQuote(sentinel) .. " ] || exit 0; "
    .. "/usr/bin/pgrep -xq -U \"$(/usr/bin/id -u)\" Hammerspoon || "
    .. "/usr/bin/open -g --env " .. K.revivedVar .. "=1 -b " .. K.bundle
end

-- plist returns the agent's plist text for sentinel.
function K.plist(sentinel)
  return table.concat({
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      .. '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    "<dict>",
    "\t<key>Label</key>",
    "\t<string>" .. xmlEscape(K.label) .. "</string>",
    "\t<key>AssociatedBundleIdentifiers</key>",
    "\t<array>",
    "\t\t<string>" .. xmlEscape(K.bundle) .. "</string>",
    "\t</array>",
    "\t<key>ProgramArguments</key>",
    "\t<array>",
    "\t\t<string>/bin/sh</string>",
    "\t\t<string>-c</string>",
    "\t\t<string>" .. xmlEscape(K.command(sentinel)) .. "</string>",
    "\t</array>",
    "\t<key>StartInterval</key>",
    "\t<integer>" .. K.seconds .. "</integer>",
    "\t<key>RunAtLoad</key>",
    "\t<false/>",
    "\t<key>ProcessType</key>",
    "\t<string>Background</string>",
    "</dict>",
    "</plist>",
    "",
  }, "\n")
end

-- loaded reports whether launchd has the agent.
local function loaded()
  local _, ok = K.run("/bin/launchctl print " .. domain .. "/" .. K.label .. " >/dev/null 2>&1")
  return ok
end

-- install writes and loads the agent for sentinel, the file whose presence means moorings is
-- still installed. An agent already written and loaded is left alone, so a Reload changes
-- nothing. It returns nil and a reason on failure.
function K.install(sentinel)
  local path, text = K.plistPath(), K.plist(sentinel)
  local same = K.readFile(path) == text
  if same and loaded() then
    return true
  end
  if not same then
    K.run("/bin/mkdir -p " .. shellQuote(dir()))
    local ok, err = K.writeFile(path, text)
    if not ok then
      return nil, "keep-alive not written: " .. tostring(err)
    end
    K.run("/bin/launchctl bootout " .. domain .. "/" .. K.label .. " >/dev/null 2>&1")
  end
  local out, ok = K.run("/bin/launchctl bootstrap " .. domain .. " " .. shellQuote(path) .. " 2>&1")
  if not ok then
    return nil, "keep-alive not loaded: " .. tostring(out)
  end
  return true
end

-- uninstall unloads the agent and deletes its plist. Either may already be gone.
function K.uninstall()
  K.run("/bin/launchctl bootout " .. domain .. "/" .. K.label .. " >/dev/null 2>&1")
  K.deleteFile(K.plistPath())
end

-- revived reports whether the agent started this Hammerspoon.
function K.revived()
  return K.getenv(K.revivedVar) ~= nil
end

return K
