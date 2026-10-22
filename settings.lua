-- settings opens a window to rebind shortcuts, edit custom sizes, set the gap,
-- the keymap and snapping, and manage workspaces, so nobody needs to open the
-- Lua file. Choices are saved in Hammerspoon settings and win over the config.

local S = {}

-- codeKeys maps a browser key code to the key name Hammerspoon binds, for the
-- codes that are not a letter, a digit or a function key.
local codeKeys = {
  ArrowLeft = "left", ArrowRight = "right", ArrowUp = "up", ArrowDown = "down",
  Enter = "return", NumpadEnter = "padenter", Backspace = "delete", Delete = "forwarddelete",
  Tab = "tab", Space = "space", Equal = "=", Minus = "-", BracketLeft = "[", BracketRight = "]",
  Backslash = "\\", Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/",
  Backquote = "`", Home = "home", End = "end", PageUp = "pageup", PageDown = "pagedown",
}

-- keyFromCode returns the Hammerspoon key name for a browser key code, which
-- names the physical key whatever the keyboard layout, or nil.
function S.keyFromCode(code)
  if type(code) ~= "string" then
    return nil
  end
  local letter = code:match("^Key(%u)$")
  if letter then
    return letter:lower()
  end
  local digit = code:match("^Digit(%d)$")
  if digit then
    return digit
  end
  local f = tonumber(code:match("^F(%d%d?)$"))
  if f and f >= 1 and f <= 20 then
    return "f" .. f
  end
  return codeKeys[code]
end

-- shortcutFrom builds a shortcut from a key press recorded in the window, or
-- returns nil and the reason it cannot be bound. A key other than a function
-- key needs Control, Option or Command, so typing is never taken over.
function S.shortcutFrom(msg)
  local key = S.keyFromCode(msg.code)
  if not key then
    return nil, "That key cannot be bound."
  end
  local mods = {}
  for _, m in ipairs({ "ctrl", "alt", "shift", "cmd" }) do
    if msg[m] then
      mods[#mods + 1] = m
    end
  end
  if not (msg.ctrl or msg.alt or msg.cmd) and not key:match("^f%d") then
    return nil, "Add Control, Option or Command to that key."
  end
  return { mods = mods, key = key }
end

-- number returns v as a number, or nil when it is missing, empty or not a number.
local function number(v)
  if v == nil then
    return nil
  end
  return tonumber(v)
end

-- sizeFrom builds a custom size entry from the fields sent by the window.
function S.sizeFrom(f)
  local title = type(f.title) == "string" and f.title:match("^%s*(.-)%s*$") or ""
  return {
    title = title ~= "" and title or nil,
    x = number(f.x), y = number(f.y), w = number(f.w), h = number(f.h),
    width = number(f.width), height = number(f.height),
  }
end

local host, actions, workspaces
local state = {}

-- attach gives settings the anchors module, the action runner and workspaces.
function S.attach(m, a, w)
  host, actions, workspaces = m, a, w
end

-- source names where the binding of action name comes from.
local function source(name)
  if host.savedShortcuts()[name] ~= nil then
    return "saved"
  end
  if type(host.config.shortcuts) == "table" and host.config.shortcuts[name] ~= nil then
    return "config"
  end
  return "default"
end

-- row describes action name for the shortcuts table.
local function row(name, map)
  return {
    name = name,
    label = actions.label(name),
    key = map[name] and actions.keyText(map[name]) or "",
    source = source(name),
  }
end

-- model gathers everything the window shows.
function S.model()
  local map, problems, sizes = actions.bindings()
  local groups = {}
  for _, fam in ipairs(actions.families) do
    for _, g in ipairs(fam.groups or { fam }) do
      local title = fam.groups and (fam.title .. ", " .. g.title) or fam.title
      local rows = {}
      for _, name in ipairs(g.names) do
        rows[#rows + 1] = row(name, map)
      end
      groups[#groups + 1] = { title = title, actions = rows }
    end
  end
  local custom = {}
  for _, s in ipairs(sizes) do
    custom[#custom + 1] = row(s.name, map)
  end
  groups[#groups + 1] = { title = "Custom sizes", actions = custom }
  local organize = {}
  for _, name in ipairs(actions.organizeNames()) do
    organize[#organize + 1] = row(name, map)
  end
  groups[#groups + 1] = { title = "Organize", actions = organize }
  local savedTitles, sizeRows = {}, {}
  for _, e in ipairs(host.savedSizes()) do
    if type(e) == "table" and e.title then
      savedTitles[e.title] = true
      sizeRows[#sizeRows + 1] = {
        title = e.title, x = e.x, y = e.y, w = e.w, h = e.h, width = e.width,
        height = e.height, saved = true,
      }
    end
  end
  for _, e in ipairs(type(host.config.sizes) == "table" and host.config.sizes or {}) do
    if type(e) == "table" and e.title and not savedTitles[e.title] then
      sizeRows[#sizeRows + 1] = {
        title = e.title, x = e.x, y = e.y, w = e.w, h = e.h, width = e.width,
        height = e.height, saved = false,
      }
    end
  end
  local ws = {}
  for _, name in ipairs(workspaces.names()) do
    ws[#ws + 1] = { name = name, tied = workspaces.tied(name) }
  end
  return {
    groups = groups,
    sizes = sizeRows,
    workspaces = ws,
    keymap = host.keymap(),
    keymaps = actions.keymapNames,
    icons = host.iconModel(),
    snap = host.snapOn(),
    gap = host.gapPx() or 0,
    problems = problems,
    notice = state.notice or "",
  }
end

-- push sends the model to the open window.
local function push()
  if state.view then
    state.view:evaluateJavaScript("moorings.render(" .. hs.json.encode(S.model()) .. ")")
  end
end

-- replaceSize puts entry in the saved sizes in place of the one titled old, or
-- of one with its own title, or at the end.
local function replaceSize(entry, old)
  local list, done = {}, false
  for _, e in ipairs(host.savedSizes()) do
    if type(e) == "table" and (e.title == old or e.title == entry.title) then
      if not done then
        list[#list + 1], done = entry, true
      end
    else
      list[#list + 1] = e
    end
  end
  if not done then
    list[#list + 1] = entry
  end
  return list
end

-- moveSizeKey carries the key saved for the size titled old over to the size
-- titled new, or drops it when new is nil.
local function moveSizeKey(old, new)
  local sc = host.savedShortcuts()["size:" .. old]
  if sc == nil or old == new then
    return
  end
  host.saveShortcut("size:" .. old, nil)
  if new then
    host.saveShortcut("size:" .. new, sc)
  end
end

-- bindable reports whether name is an action or a custom size in effect.
local function bindable(name)
  if type(name) ~= "string" then
    return false
  end
  if actions.known(name) then
    return true
  end
  local _, _, sizes = actions.bindings()
  for _, s in ipairs(sizes) do
    if s.name == name then
      return true
    end
  end
  return false
end

-- handlers maps each message type from the window to what it does. Each
-- returns a notice to show, or nil.
local handlers = {
  ready = function() end,
  record = function(m)
    if m.on == true then
      actions.suspend()
    else
      actions.refresh()
    end
  end,
  bind = function(m)
    if not bindable(m.action) then
      return "Unknown action " .. tostring(m.action) .. "."
    end
    local sc, why = S.shortcutFrom(m)
    if not sc then
      actions.refresh()
      return why
    end
    host.saveShortcut(m.action, sc)
    return actions.label(m.action) .. " is now " .. actions.keyText(sc) .. "."
  end,
  unbind = function(m)
    if bindable(m.action) then
      host.saveShortcut(m.action, false)
    end
  end,
  reset = function(m)
    if bindable(m.action) then
      host.saveShortcut(m.action, nil)
    end
  end,
  saveSize = function(m)
    local entry = S.sizeFrom(type(m.size) == "table" and m.size or {})
    local _, problems = actions.sizes({ entry })
    if #problems > 0 then
      return "Not saved: " .. problems[1] .. "."
    end
    host.saveSizes(replaceSize(entry, m.old))
    if type(m.old) == "string" then
      moveSizeKey(m.old, entry.title)
    end
    return entry.title .. " is saved."
  end,
  deleteSize = function(m)
    local list = {}
    for _, e in ipairs(host.savedSizes()) do
      if not (type(e) == "table" and e.title == m.title) then
        list[#list + 1] = e
      end
    end
    host.saveSizes(list)
    if type(m.title) == "string" then
      moveSizeKey(m.title, nil)
    end
  end,
  gap = function(m)
    local n = tonumber(m.value)
    if not n or n ~= math.floor(n) or n < 0 or n > 100 then
      return "The gap must be a whole number from 0 to 100."
    end
    host.saveGap(n)
  end,
  keymap = function(m)
    if actions.keymaps[m.name] then
      host.setKeymap(m.name)
    end
  end,
  snap = function(m)
    host.setSnap(m.on == true)
  end,
  recall = function(m)
    workspaces.recall(m.name)
  end,
  tie = function(m)
    workspaces.tie(m.name)
  end,
  deleteWorkspace = function(m)
    workspaces.delete(m.name)
  end,
  iconPick = function(m)
    local ok, why = host.pickIcon(m.name)
    if not ok then
      return why
    end
  end,
  iconCustom = function(m)
    local ok, why = host.setCustomIcon(m.text)
    if not ok then
      return why
    end
  end,
  iconDefault = function()
    host.defaultIcon()
  end,
  iconSurprise = function()
    host.surpriseIcon()
  end,
  iconUndo = function()
    local ok, why = host.undoIcon()
    if not ok then
      return why
    end
  end,
  iconFolder = function()
    host.openIconDir()
  end,
  saveWorkspace = function(m)
    local name = type(m.name) == "string" and m.name:match("^%s*(.-)%s*$") or ""
    if name == "" then
      return "Name the workspace first."
    end
    workspaces.save(name)
    return name .. " is saved."
  end,
}

-- handle runs one message from the window and returns the notice to show, or nil.
function S.handle(m)
  local fn = type(m) == "table" and handlers[m.type]
  if not fn then
    host.log("the settings window sent an unknown message")
    return nil
  end
  return fn(m)
end

-- receive handles one message from the window and sends the new state back.
function S.receive(m)
  state.notice = S.handle(m)
  push()
end

-- center returns a w by h frame centered on the main screen.
local function center(w, h)
  local f = hs.screen.mainScreen():frame()
  return { x = f.x + math.floor((f.w - w) / 2), y = f.y + math.floor((f.h - h) / 2), w = w, h = h }
end

-- open shows the settings window, or brings it forward when it is open.
function S.open()
  if state.view then
    state.view:show():bringToFront(true)
    return
  end
  local file = io.open(host.path("settings.html"), "r")
  if not file then
    host.log("settings.html is missing from the moorings folder")
    return
  end
  local html = file:read("a")
  file:close()
  local content = hs.webview.usercontent.new("moorings"):setCallback(function(msg)
    local ok, err = pcall(S.receive, msg.body)
    if not ok then
      host.log(err)
    end
  end)
  state.view = hs.webview.new(center(820, 640), { developerExtrasEnabled = false }, content)
    :windowStyle({ "titled", "closable", "resizable", "miniaturizable" })
    :windowTitle("moorings settings")
    :allowTextEntry(true)
    :deleteOnClose(true)
    :windowCallback(function(action)
      if action == "closing" then
        state.view = nil
        actions.refresh()
      end
    end)
    :html(html)
    :show()
    :bringToFront(true)
  hs.focus()
end

return S
