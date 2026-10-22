-- actions runs window actions on the focused window and binds them to
-- shortcuts. anchors attaches itself so actions can read the work area, the
-- pins and the frozen state.

local geometry = require("geometry")
local tile = require("tile")

local A = {}

-- keymaps holds the built-in shortcut sets by name. rectangle is Rectangle's
-- recommended set and spectacle is Spectacle's default set.
A.keymaps = {}

A.keymaps.rectangle = {
  ["left-half"] = { mods = { "ctrl", "alt" }, key = "left" },
  ["right-half"] = { mods = { "ctrl", "alt" }, key = "right" },
  ["top-half"] = { mods = { "ctrl", "alt" }, key = "up" },
  ["bottom-half"] = { mods = { "ctrl", "alt" }, key = "down" },
  ["top-left"] = { mods = { "ctrl", "alt" }, key = "u" },
  ["top-right"] = { mods = { "ctrl", "alt" }, key = "i" },
  ["bottom-left"] = { mods = { "ctrl", "alt" }, key = "j" },
  ["bottom-right"] = { mods = { "ctrl", "alt" }, key = "k" },
  ["first-third"] = { mods = { "ctrl", "alt" }, key = "d" },
  ["center-third"] = { mods = { "ctrl", "alt" }, key = "f" },
  ["last-third"] = { mods = { "ctrl", "alt" }, key = "g" },
  ["first-two-thirds"] = { mods = { "ctrl", "alt" }, key = "e" },
  ["center-two-thirds"] = { mods = { "ctrl", "alt" }, key = "r" },
  ["last-two-thirds"] = { mods = { "ctrl", "alt" }, key = "t" },
  maximize = { mods = { "ctrl", "alt" }, key = "return" },
  ["maximize-height"] = { mods = { "ctrl", "alt", "shift" }, key = "up" },
  center = { mods = { "ctrl", "alt" }, key = "c" },
  larger = { mods = { "ctrl", "alt" }, key = "=" },
  smaller = { mods = { "ctrl", "alt" }, key = "-" },
  restore = { mods = { "ctrl", "alt" }, key = "delete" },
  ["previous-display"] = { mods = { "ctrl", "alt", "cmd" }, key = "left" },
  ["next-display"] = { mods = { "ctrl", "alt", "cmd" }, key = "right" },
}

-- Spectacle's next and previous third walk the thirds, which first-third and
-- last-third do on a repeat press.
A.keymaps.spectacle = {
  center = { mods = { "alt", "cmd" }, key = "c" },
  maximize = { mods = { "alt", "cmd" }, key = "f" },
  ["left-half"] = { mods = { "alt", "cmd" }, key = "left" },
  ["right-half"] = { mods = { "alt", "cmd" }, key = "right" },
  ["top-half"] = { mods = { "alt", "cmd" }, key = "up" },
  ["bottom-half"] = { mods = { "alt", "cmd" }, key = "down" },
  ["top-left"] = { mods = { "ctrl", "cmd" }, key = "left" },
  ["bottom-left"] = { mods = { "ctrl", "shift", "cmd" }, key = "left" },
  ["top-right"] = { mods = { "ctrl", "cmd" }, key = "right" },
  ["bottom-right"] = { mods = { "ctrl", "shift", "cmd" }, key = "right" },
  ["next-display"] = { mods = { "ctrl", "alt", "cmd" }, key = "right" },
  ["previous-display"] = { mods = { "ctrl", "alt", "cmd" }, key = "left" },
  ["first-third"] = { mods = { "ctrl", "alt" }, key = "right" },
  ["last-third"] = { mods = { "ctrl", "alt" }, key = "left" },
  larger = { mods = { "ctrl", "alt", "shift" }, key = "right" },
  smaller = { mods = { "ctrl", "alt", "shift" }, key = "left" },
  restore = { mods = { "alt", "cmd" }, key = "z" },
}

-- keymapNames lists the built-in keymaps in menu order.
A.keymapNames = { "rectangle", "spectacle" }

-- step is how many points larger and smaller move each free edge.
A.step = 30

-- families groups the actions for the Window menu folder. A family with groups
-- holds a folder per group.
A.families = {
  {
    title = "Halves",
    names = { "left-half", "right-half", "center-half", "top-half", "bottom-half" },
  },
  { title = "Quarters", names = { "top-left", "top-right", "bottom-left", "bottom-right" } },
  {
    title = "Thirds",
    names = { "first-third", "center-third", "last-third", "first-two-thirds",
      "center-two-thirds", "last-two-thirds" },
  },
  {
    title = "Fourths",
    names = { "first-fourth", "second-fourth", "third-fourth", "last-fourth",
      "first-three-fourths", "center-three-fourths", "last-three-fourths" },
  },
  {
    title = "Grids",
    groups = {
      { title = "Sixths", names = geometry.grids.sixths },
      { title = "Eighths", names = geometry.grids.eighths },
      { title = "Ninths", names = geometry.grids.ninths },
      { title = "Corner thirds", names = geometry.grids.cornerThirds },
    },
  },
  {
    title = "Size and move",
    names = { "maximize", "almost-maximize", "maximize-height", "center", "center-prominently",
      "larger", "smaller", "move-left", "move-right", "move-up", "move-down", "restore" },
  },
  { title = "Displays", names = { "previous-display", "next-display" } },
}

-- special lists the actions that are not positions in geometry.
local special = {
  larger = true,
  smaller = true,
  restore = true,
  ["next-display"] = true,
  ["previous-display"] = true,
}

-- modOrder lists the modifiers in the order macOS menus show them.
local modOrder = { "ctrl", "alt", "shift", "cmd" }

-- modGlyphs maps a modifier to its menu glyph.
local modGlyphs = { ctrl = "⌃", alt = "⌥", shift = "⇧", cmd = "⌘" }

-- modAliases maps the other names Hammerspoon accepts to one spelling.
local modAliases = { control = "ctrl", option = "alt", opt = "alt", command = "cmd" }

-- keyGlyphs maps a key name to its menu glyph.
local keyGlyphs = {
  left = "←", right = "→", up = "↑", down = "↓", ["return"] = "↩", delete = "⌫",
  forwarddelete = "⌦", space = "Space", tab = "⇥", escape = "⎋",
}

local host
local state = {
  -- last maps a window id to the action, press count and frame of its last action.
  last = {},
  -- hotkeys holds the bound shortcuts.
  hotkeys = {},
  -- mouse maps a mouse button number to the action it runs.
  mouse = {},
  -- off is set while an app that turns shortcuts off is frontmost.
  off = false,
}

-- attach gives actions the anchors module it reads state from.
function A.attach(m)
  host = m
  state.last = {}
end

-- sizePrefix starts the action name of every custom size.
local sizePrefix = "size:"

-- workspacePrefix starts the action name that recalls a saved workspace.
local workspacePrefix = "workspace:"

-- known reports whether name is an action moorings can run. A workspace name
-- counts, since workspaces are saved after the shortcuts are bound.
function A.known(name)
  return special[name] == true or tile.handles(name)
    or (name:sub(1, #workspacePrefix) == workspacePrefix and #name > #workspacePrefix)
    or geometry.position(name, { x = 0, y = 0, w = 100, h = 100 }) ~= nil
end

-- label turns an action name into menu text, so left-half reads Left half and
-- a custom size reads as its title.
function A.label(name)
  if name:sub(1, #sizePrefix) == sizePrefix then
    return name:sub(#sizePrefix + 1)
  end
  local s = name:gsub("-", " ")
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- share reports whether v is nil or a number from lo to 1.
local function share(v, lo)
  return v == nil or (type(v) == "number" and v >= lo and v <= 1)
end

-- points reports whether v is nil or a positive number.
local function points(v)
  return v == nil or (type(v) == "number" and v > 0)
end

-- sizes checks the custom sizes from the config and returns the valid ones,
-- each with its action name, plus the problems found.
function A.sizes(list)
  local out, problems, seen = {}, {}, {}
  for i, e in ipairs(type(list) == "table" and list or {}) do
    local title = type(e) == "table" and e.title
    if type(title) ~= "string" or title == "" then
      problems[#problems + 1] = "sizes entry " .. i .. " needs a title: ignoring it"
    elseif seen[title] then
      problems[#problems + 1] = "sizes has two entries titled " .. title .. ": the first wins"
    elseif not (share(e.x, 0) and share(e.y, 0) and share(e.w, 1e-9) and share(e.h, 1e-9))
      or (e.x or 0) + (e.w or 1) > 1 + 1e-9 or (e.y or 0) + (e.h or 1) > 1 + 1e-9 then
      problems[#problems + 1] = "size " .. title
        .. " needs x, y, w and h between 0 and 1 that fit the area: ignoring it"
    elseif not (points(e.width) and points(e.height)) then
      problems[#problems + 1] = "size " .. title .. " needs a width and height above 0: ignoring it"
    else
      seen[title] = true
      out[#out + 1] = { name = sizePrefix .. title, spec = e, shortcut = e.shortcut }
    end
  end
  return out, problems
end

-- sizeSpec returns the config entry of the custom size action name, or nil.
local function sizeSpec(name)
  for _, s in ipairs((A.sizes(host.sizeList()))) do
    if s.name == name then
      return s.spec
    end
  end
  return nil
end

-- maxGap is the widest gap the config may ask for.
local maxGap = 100

-- gap returns the gap between windows in points from the config.
function A.gap()
  local g = host.gapPx()
  if g == nil then
    return 0
  end
  if type(g) ~= "number" or g < 0 or g > maxGap then
    host.log("gapPx must be a number from 0 to " .. maxGap .. ": using 0")
    return 0
  end
  return math.floor(g)
end

-- normalMods returns mods with aliases resolved, in menu order, or nil when one
-- is unknown.
local function normalMods(mods)
  local have = {}
  for _, m in ipairs(mods) do
    local name = tostring(m):lower()
    name = modAliases[name] or name
    if not modGlyphs[name] then
      return nil
    end
    have[name] = true
  end
  local out = {}
  for _, m in ipairs(modOrder) do
    if have[m] then
      out[#out + 1] = m
    end
  end
  return out
end

-- keyText returns the menu glyphs of shortcut sc, such as ⌃⌥←.
function A.keyText(sc)
  local out = {}
  for _, m in ipairs(sc.mods) do
    out[#out + 1] = modGlyphs[m]
  end
  out[#out + 1] = keyGlyphs[sc.key] or sc.key:upper()
  return table.concat(out)
end

-- wellFormed reports whether sc has a mods table and a key string.
local function wellFormed(sc)
  return type(sc) == "table" and type(sc.mods) == "table" and type(sc.key) == "string"
end

-- shortcuts merges overrides and extra onto the keymap named keymap, Rectangle's
-- by default, and returns the binding for each action plus the problems found.
-- extra maps more action names, such as custom sizes, to their shortcuts, and
-- also makes those names valid in overrides. An override of false removes a
-- binding. When two actions share a key, one the config set beats a default,
-- and otherwise the first in name order keeps it.
function A.shortcuts(overrides, extra, keymap)
  local merged, explicit, problems = {}, {}, {}
  for name, sc in pairs(A.keymaps[keymap] or A.keymaps.rectangle) do
    merged[name] = sc
  end
  local extraNames = {}
  for name, sc in pairs(extra or {}) do
    extraNames[name] = true
    if wellFormed(sc) then
      merged[name], explicit[name] = sc, true
    elseif sc ~= false then
      problems[#problems + 1] = "shortcut for " .. name .. " needs mods and key: ignoring it"
    end
  end
  for name, sc in pairs(overrides or {}) do
    if not (A.known(name) or extraNames[name]) then
      problems[#problems + 1] = "shortcuts names unknown action " .. tostring(name)
        .. ": ignoring it"
    elseif sc == false then
      merged[name] = nil
    elseif not wellFormed(sc) then
      problems[#problems + 1] = "shortcut for " .. name .. " needs mods and key: ignoring it"
    else
      merged[name], explicit[name] = sc, true
    end
  end
  local names = {}
  for name in pairs(merged) do
    names[#names + 1] = name
  end
  table.sort(names, function(a, b)
    if explicit[a] ~= explicit[b] then
      return explicit[a] == true
    end
    return a < b
  end)
  local out, owner = {}, {}
  for _, name in ipairs(names) do
    local mods = normalMods(merged[name].mods)
    if not mods then
      problems[#problems + 1] = "shortcut for " .. name .. " has an unknown modifier: ignoring it"
    else
      local sc = { mods = mods, key = merged[name].key:lower() }
      local combo = A.keyText(sc)
      if owner[combo] then
        problems[#problems + 1] = string.format("%s and %s share %s: %s keeps it",
          owner[combo], name, combo, owner[combo])
      else
        owner[combo], out[name] = name, sc
      end
    end
  end
  return out, problems
end

-- near reports whether two frames match within the configured tolerance.
local function near(a, b)
  local t = host.config.tolerance
  return math.abs(a.x - b.x) <= t and math.abs(a.y - b.y) <= t
    and math.abs(a.w - b.w) <= t and math.abs(a.h - b.h) <= t
end

-- screens returns every screen ordered left to right, then top to bottom.
local function screens()
  local list = {}
  for i, s in ipairs(hs.screen.allScreens()) do
    list[i] = s
  end
  table.sort(list, function(a, b)
    local fa, fb = a:frame(), b:frame()
    if fa.x ~= fb.x then
      return fa.x < fb.x
    end
    return fa.y < fb.y
  end)
  return list
end

-- neighbor returns the screen dir steps from s in screen order, wrapping.
local function neighbor(s, dir)
  local list = screens()
  for i, other in ipairs(list) do
    if other:id() == s:id() then
      return list[(i - 1 + dir) % #list + 1]
    end
  end
  return s
end

-- actionable reports whether an action may move win, logging when win is pinned.
local function actionable(win)
  if not win or win:id() == nil or not win:isStandard() or win:isFullScreen() then
    return false
  end
  if host.pinned(win) then
    host.log("the window is pinned: window actions leave pins alone")
    return false
  end
  return true
end

-- frameFor returns the frame action name gives win on screen s, which
-- defaults to win's own screen, and the press count for a cycling action.
local function frameFor(name, win, s)
  local cur = win:frame()
  s = s or win:screen()
  if name == "next-display" or name == "previous-display" then
    local to = neighbor(s, name == "next-display" and 1 or -1)
    if to:id() == s:id() then
      return nil
    end
    return geometry.transfer(cur, host.area(s), host.area(to))
  end
  local area, g = host.area(s), A.gap()
  if name == "larger" or name == "smaller" then
    return geometry.resize(area, cur, name == "larger" and A.step or -A.step, g)
  end
  if name:sub(1, #sizePrefix) == sizePrefix then
    local spec = sizeSpec(name)
    return spec and geometry.custom(area, spec, g)
  end
  local last, i = state.last[win:id()], 1
  if last and last.name == name and near(cur, last.frame) then
    i = last.i + 1
  end
  return geometry.cycle(name, i, area, cur, g), i
end

-- bindings returns the shortcut for every action, custom sizes included, and
-- the problems found in the shortcuts and sizes config.
local function bindings()
  local sizes, problems = A.sizes(host.sizeList())
  local extra = {}
  for _, s in ipairs(sizes) do
    if s.shortcut == nil then
      extra[s.name] = false
    else
      extra[s.name] = s.shortcut
    end
  end
  local map, more = A.shortcuts(host.shortcutOverrides(), extra, host.keymap())
  for _, p in ipairs(more) do
    problems[#problems + 1] = p
  end
  return map, problems, sizes
end

A.bindings = bindings

-- organizeNames returns the organize actions in menu order.
function A.organizeNames()
  return tile.names
end

-- preview returns the frame action name would give win on screen s, without
-- moving it.
function A.preview(win, name, s)
  return (frameFor(name, win, s))
end

-- run applies action name to the focused window, organizes its screen for an
-- organize action, or recalls a workspace, and reports whether anything moved.
function A.run(name)
  if tile.handles(name) then
    return not host.paused() and tile.run(name)
  end
  if name:sub(1, #workspacePrefix) == workspacePrefix then
    return host.recallWorkspace(name:sub(#workspacePrefix + 1))
  end
  return A.apply(hs.window.focusedWindow(), name)
end

-- apply applies action name to win on screen s, which defaults to win's own
-- screen, and reports whether it moved. Nothing runs while the layout is frozen. On a
-- pin, Maximize lifts or lowers it and Restore re-moors it.
function A.apply(win, name, s)
  if host.paused() then
    return false
  end
  if win and (name == "maximize" or name == "restore") and host.pinned(win) then
    if name == "maximize" then
      return host.toggleLift(win)
    end
    return host.remoor(win)
  end
  if not actionable(win) then
    return false
  end
  local id = win:id()
  if name == "restore" then
    state.last[id] = nil
    return host.restore(win)
  end
  local frame, i = frameFor(name, win, s)
  if not frame then
    return false
  end
  host.save(win)
  win:setFrame(frame)
  state.last[id] = { name = name, i = i or 1, frame = win:frame() }
  return true
end

-- runLogged runs action name and logs an error instead of raising it.
local function runLogged(name)
  local ok, err = pcall(A.run, name)
  if not ok then
    host.log(err)
  end
  return ok and err
end

-- runnable reports whether name is an action or a custom size in the config.
local function runnable(name)
  return type(name) == "string" and (A.known(name) or sizeSpec(name) ~= nil)
end

-- mouseButtons checks the mouse button bindings from the config and returns
-- the valid ones plus the problems found. Buttons 0 and 1 are the primary and
-- secondary buttons and cannot be bound.
function A.mouseButtons(cfg, sizes)
  local out, problems = {}, {}
  local sized = {}
  for _, s in ipairs(sizes or {}) do
    sized[s.name] = true
  end
  for button, name in pairs(type(cfg) == "table" and cfg or {}) do
    if math.type(button) ~= "integer" or button < 2 or button > 31 then
      problems[#problems + 1] = "mouseButtons has button " .. tostring(button)
        .. ": use a number from 2 to 31"
    elseif type(name) ~= "string" or not (A.known(name) or sized[name]) then
      problems[#problems + 1] = "mouseButtons names unknown action " .. tostring(name)
        .. " for button " .. button .. ": ignoring it"
    else
      out[button] = name
    end
  end
  return out, problems
end

-- mouse runs the action bound to a mouse button. A bound button's events are
-- swallowed so the app under the cursor does not also act on them. Unbound
-- buttons, and every button while frozen or while an ignored app is in front,
-- pass on untouched.
function A.mouse(e)
  local ok, swallow = pcall(function()
    local button = e:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
    local name = state.mouse[button]
    if not name or state.off or host.paused() then
      return false
    end
    if e:getType() == hs.eventtap.event.types.otherMouseDown then
      hs.timer.doAfter(0, function() runLogged(name) end)
    end
    return true
  end)
  if not ok then
    host.log(swallow)
    return false
  end
  return swallow
end

-- url runs the action a hammerspoon://moorings?action=name link asks for.
function A.url(params)
  local name = type(params) == "table" and params.action or nil
  if not runnable(name) then
    host.log("a moorings link asked for unknown action " .. tostring(name))
    return false
  end
  return runLogged(name)
end

-- refresh enables the shortcuts, or disables them while an ignored app is frontmost.
function A.refresh()
  local front = hs.application.frontmostApplication()
  local off = front ~= nil and host.shortcutsIgnored(front:bundleID())
  state.off = off
  for _, hk in pairs(state.hotkeys) do
    if off then
      hk:disable()
    else
      hk:enable()
    end
  end
end

-- suspend turns every shortcut off until the next refresh, so a key press
-- being recorded in the settings window reaches the window.
function A.suspend()
  for _, hk in pairs(state.hotkeys) do
    hk:disable()
  end
end

-- unbind removes every bound shortcut.
function A.unbind()
  for _, hk in pairs(state.hotkeys) do
    hk:delete()
  end
  state.hotkeys = {}
end

-- bind binds every shortcut and mouse button in effect and the moorings URL,
-- watches app switches for ignored apps, and returns the problems found.
function A.bind()
  A.unbind()
  local map, problems, sizes = bindings()
  for name, sc in pairs(map) do
    local ok, hk = pcall(hs.hotkey.new, sc.mods, sc.key, function() runLogged(name) end)
    if ok and hk then
      state.hotkeys[name] = hk
    else
      problems[#problems + 1] = "shortcut for " .. name .. " has an unknown key " .. sc.key
        .. ": ignoring it"
    end
  end
  local buttons, more = A.mouseButtons(host.config.mouseButtons, sizes)
  for _, p in ipairs(more) do
    problems[#problems + 1] = p
  end
  state.mouse = buttons
  if state.mouseTap then
    state.mouseTap:stop()
    state.mouseTap = nil
  end
  if next(buttons) then
    local types = hs.eventtap.event.types
    state.mouseTap = hs.eventtap.new({ types.otherMouseDown, types.otherMouseUp }, A.mouse):start()
  end
  hs.urlevent.bind("moorings", function(_, params) A.url(params) end)
  if not state.watcher then
    state.watcher = hs.application.watcher.new(function(_, event)
      if event == hs.application.watcher.activated then
        pcall(A.refresh)
      end
    end):start()
  end
  A.refresh()
  return problems
end

-- items builds menu entries for names, each showing its shortcut.
local function items(names, map, frozen)
  local out = {}
  for _, name in ipairs(names) do
    local title = A.label(name)
    if map[name] then
      title = title .. "  " .. A.keyText(map[name])
    end
    out[#out + 1] = {
      title = title,
      action = name,
      disabled = frozen,
      fn = function() runLogged(name) end,
    }
  end
  return out
end

-- menu builds the Window folder: one folder per family, one for the custom
-- sizes and one for organizing, which ends with the extra entries given. Each
-- entry shows its shortcut, so the menu doubles as the cheat sheet.
function A.menu(extra)
  local map, _, sizes = bindings()
  local frozen = host.paused()
  local out = {}
  for _, fam in ipairs(A.families) do
    local sub
    if fam.groups then
      sub = {}
      for _, g in ipairs(fam.groups) do
        sub[#sub + 1] = { title = g.title, menu = items(g.names, map, frozen) }
      end
    else
      sub = items(fam.names, map, frozen)
    end
    out[#out + 1] = { title = fam.title, menu = sub }
  end
  local names = {}
  for i, s in ipairs(sizes) do
    names[i] = s.name
  end
  local custom = items(names, map, frozen)
  if #custom == 0 then
    custom = { { title = "No sizes in the config", disabled = true } }
  end
  out[#out + 1] = { title = "Custom sizes", menu = custom }
  local organize = items(tile.names, map, frozen)
  for _, it in ipairs(extra or {}) do
    organize[#organize + 1] = it
  end
  out[#out + 1] = { title = "Organize", menu = organize }
  return out
end

return A
