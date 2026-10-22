-- actions runs window actions on the focused window and binds them to
-- shortcuts. anchors attaches itself so actions can read the work area, the
-- pins and the frozen state.

local geometry = require("geometry")

local A = {}

-- keymap is Rectangle's recommended shortcut set, by action name.
A.keymap = {
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

-- step is how many points larger and smaller move each free edge.
A.step = 30

-- families groups the actions for the Window menu folder. A family with groups
-- holds a folder per group.
A.families = {
  { title = "Halves", names = { "left-half", "right-half", "center-half", "top-half", "bottom-half" } },
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
}

-- attach gives actions the anchors module it reads state from.
function A.attach(m)
  host = m
  state.last = {}
end

-- known reports whether name is an action moorings can run.
function A.known(name)
  return special[name] == true or geometry.position(name, { x = 0, y = 0, w = 100, h = 100 }) ~= nil
end

-- label turns an action name into menu text, so left-half reads Left half.
function A.label(name)
  local s = name:gsub("-", " ")
  return s:sub(1, 1):upper() .. s:sub(2)
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

-- shortcuts merges overrides onto the keymap and returns the binding for each
-- action plus the problems found. An override of false removes a binding. Two
-- actions on one key keep it for the first in name order.
function A.shortcuts(overrides)
  local merged, problems = {}, {}
  for name, sc in pairs(A.keymap) do
    merged[name] = sc
  end
  for name, sc in pairs(overrides or {}) do
    if not A.known(name) then
      problems[#problems + 1] = "shortcuts names unknown action " .. tostring(name) .. ": ignoring it"
    elseif sc == false then
      merged[name] = nil
    elseif type(sc) ~= "table" or type(sc.mods) ~= "table" or type(sc.key) ~= "string" then
      problems[#problems + 1] = "shortcut for " .. name .. " needs mods and key: ignoring it"
    else
      merged[name] = sc
    end
  end
  local names = {}
  for name in pairs(merged) do
    names[#names + 1] = name
  end
  table.sort(names)
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

-- target returns the focused window when an action may move it, or nil.
local function target()
  local win = hs.window.focusedWindow()
  if not win or win:id() == nil or not win:isStandard() or win:isFullScreen() then
    return nil
  end
  if host.pinned(win) then
    host.log("the focused window is pinned: window actions leave pins alone")
    return nil
  end
  return win
end

-- frameFor returns the frame action name gives win, and the press count for a
-- cycling action.
local function frameFor(name, win)
  local cur, s = win:frame(), win:screen()
  if name == "next-display" or name == "previous-display" then
    local to = neighbor(s, name == "next-display" and 1 or -1)
    if to:id() == s:id() then
      return nil
    end
    return geometry.transfer(cur, host.area(s), host.area(to))
  end
  local area = host.area(s)
  if name == "larger" or name == "smaller" then
    return geometry.resize(area, cur, name == "larger" and A.step or -A.step)
  end
  local last, i = state.last[win:id()], 1
  if last and last.name == name and near(cur, last.frame) then
    i = last.i + 1
  end
  return geometry.cycle(name, i, area, cur), i
end

-- run applies action name to the focused window and reports whether it moved.
-- Nothing runs while the layout is frozen.
function A.run(name)
  if host.paused() then
    return false
  end
  local win = target()
  if not win then
    return false
  end
  local id = win:id()
  if name == "restore" then
    state.last[id] = nil
    return host.restore(win)
  end
  local frame, i = frameFor(name, win)
  if not frame then
    return false
  end
  host.save(win)
  win:setFrame(frame)
  state.last[id] = { name = name, i = i or 1, frame = win:frame() }
  return true
end

-- refresh enables the shortcuts, or disables them while an ignored app is frontmost.
function A.refresh()
  local front = hs.application.frontmostApplication()
  local off = front ~= nil and host.shortcutsIgnored(front:bundleID())
  for _, hk in pairs(state.hotkeys) do
    if off then
      hk:disable()
    else
      hk:enable()
    end
  end
end

-- unbind removes every bound shortcut.
function A.unbind()
  for _, hk in pairs(state.hotkeys) do
    hk:delete()
  end
  state.hotkeys = {}
end

-- bind binds every shortcut in effect, watches app switches for ignored apps,
-- and returns the problems found.
function A.bind()
  A.unbind()
  local map, problems = A.shortcuts(host.config.shortcuts)
  for name, sc in pairs(map) do
    local ok, hk = pcall(hs.hotkey.new, sc.mods, sc.key, function()
      local ran, err = pcall(A.run, name)
      if not ran then
        host.log(err)
      end
    end)
    if ok and hk then
      state.hotkeys[name] = hk
    else
      problems[#problems + 1] = "shortcut for " .. name .. " has an unknown key " .. sc.key
        .. ": ignoring it"
    end
  end
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
      fn = function()
        local ok, err = pcall(A.run, name)
        if not ok then
          host.log(err)
        end
      end,
    }
  end
  return out
end

-- menu builds the Window folder: one folder per family, each entry showing its
-- shortcut, so the menu doubles as the cheat sheet.
function A.menu()
  local map = A.shortcuts(host.config.shortcuts)
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
  return out
end

return A
