-- actions_test checks the parts of actions.lua that run without Hammerspoon:
-- labels, shortcut text, keymap merging and the menu families. Run it from the
-- repo root with: lua tests/actions_test.lua

package.path = "./?.lua;" .. package.path

local A = require("actions")
local G = require("geometry")
local failures, passes = 0, 0

-- check records a failure when cond is false.
local function check(name, cond, msg)
  if cond then
    passes = passes + 1
  else
    failures = failures + 1
    print("FAIL " .. name .. ": " .. (msg or "condition false"))
  end
end

-- has reports whether any problem contains text.
local function has(problems, text)
  for _, p in ipairs(problems) do
    if p:find(text, 1, true) then return true end
  end
  return false
end

local tests = {}

-- Test 0: Labels read as plain words.
tests[#tests + 1] = function()
  check("t0 half", A.label("left-half") == "Left half", A.label("left-half"))
  check("t0 grid", A.label("top-center-left-eighth") == "Top center left eighth")
  check("t0 one word", A.label("maximize") == "Maximize")
end

-- Test 1: Shortcut text uses menu glyphs in macOS order.
tests[#tests + 1] = function()
  check("t1 arrow", A.keyText({ mods = { "ctrl", "alt" }, key = "left" }) == "⌃⌥←")
  check("t1 letter", A.keyText({ mods = { "ctrl", "alt", "cmd" }, key = "u" }) == "⌃⌥⌘U")
  check("t1 delete", A.keyText({ mods = { "ctrl", "alt" }, key = "delete" }) == "⌃⌥⌫")
end

-- Test 2: The keymap alone binds every Rectangle default with no problems.
tests[#tests + 1] = function()
  local map, problems = A.shortcuts({})
  local n = 0
  for _ in pairs(map) do n = n + 1 end
  check("t2 count", n == 22, tostring(n))
  check("t2 clean", #problems == 0, table.concat(problems, "; "))
  check("t2 left", A.keyText(map["left-half"]) == "⌃⌥←")
  check("t2 height", A.keyText(map["maximize-height"]) == "⌃⌥⇧↑")
  check("t2 next display", A.keyText(map["next-display"]) == "⌃⌥⌘→")
  for name in pairs(map) do
    check("t2 known " .. name, A.known(name))
  end
end

-- Test 3: Overrides rebind, unbind, normalize aliases and report bad entries.
tests[#tests + 1] = function()
  local map, problems = A.shortcuts({
    ["left-half"] = { mods = { "command", "Option" }, key = "H" },
    maximize = false,
    center = { mods = { "ctrl", "alt" }, key = "k" },
    sideways = { mods = { "ctrl" }, key = "s" },
    ["top-half"] = { key = "t" },
    ["bottom-half"] = { mods = { "hyper" }, key = "b" },
  })
  check("t3 rebound", map["left-half"] and A.keyText(map["left-half"]) == "⌥⌘H")
  check("t3 unbound", map.maximize == nil)
  check("t3 config beats default", map.center ~= nil and map["bottom-right"] == nil)
  check("t3 clash said", has(problems, "center and bottom-right share ⌃⌥K: center keeps it"))
  check("t3 unknown", has(problems, "unknown action sideways"))
  check("t3 malformed", has(problems, "shortcut for top-half needs mods and key"))
  check("t3 malformed keeps default", map["top-half"] ~= nil)
  check("t3 bad modifier", has(problems, "shortcut for bottom-half has an unknown modifier"))
  check("t3 bad modifier dropped", map["bottom-half"] == nil)
end

-- Test 4: The families list every geometry position once plus the special actions.
tests[#tests + 1] = function()
  local seen, dupes = {}, {}
  for _, fam in ipairs(A.families) do
    local lists = fam.groups or { fam }
    for _, g in ipairs(lists) do
      for _, name in ipairs(g.names) do
        if seen[name] then dupes[#dupes + 1] = name end
        seen[name] = true
      end
    end
  end
  check("t4 no dupes", #dupes == 0, table.concat(dupes, ","))
  for _, name in ipairs(G.names()) do
    check("t4 listed " .. name, seen[name] == true)
  end
  for _, name in ipairs({ "larger", "smaller", "restore", "next-display", "previous-display" }) do
    check("t4 special " .. name, seen[name] == true and A.known(name))
  end
  check("t4 unknown", not A.known("sideways"))
  for _, name in ipairs(require("tile").names) do
    check("t4 organize " .. name, A.known(name))
  end
end

-- Test 5: Two config keys on one key keep it for the first in name order, and defaults that
-- do not clash stay.
tests[#tests + 1] = function()
  local map, problems = A.shortcuts({
    center = { mods = { "ctrl" }, key = "x" },
    maximize = { mods = { "ctrl" }, key = "x" },
  })
  check("t5 first explicit wins", map.center ~= nil and map.maximize == nil)
  check("t5 said", has(problems, "center and maximize share ⌃X: center keeps it"))
  check("t5 default kept", map["left-half"] ~= nil)
end

-- Test 6: Valid custom sizes come back with action names and invalid ones are reported.
tests[#tests + 1] = function()
  local sizes, problems = A.sizes({
    { title = "Reading", x = 0.25, w = 0.5, shortcut = { mods = { "ctrl", "alt" }, key = "y" } },
    { title = "Video", width = 1280, height = 720 },
    { x = 0.1 },
    { title = "Reading", w = 0.3 },
    { title = "Wide", x = 0.5, w = 0.6 },
    { title = "Flat", h = 0 },
    { title = "Negative", y = -0.1 },
    { title = "Tiny", width = 0 },
    { title = "Words", w = "half" },
    { title = "Thin", w = 0 },
  })
  check("t6 count", #sizes == 2, tostring(#sizes))
  check("t6 names", sizes[1].name == "size:Reading" and sizes[2].name == "size:Video")
  check("t6 shortcut", sizes[1].shortcut.key == "y" and sizes[2].shortcut == nil)
  check("t6 no title", has(problems, "sizes entry 3 needs a title"))
  check("t6 dupe", has(problems, "two entries titled Reading: the first wins"))
  check("t6 overflow", has(problems, "size Wide needs x, y, w and h between 0 and 1"))
  check("t6 zero", has(problems, "size Flat needs x, y, w and h"))
  check("t6 negative", has(problems, "size Negative needs x, y, w and h"))
  check("t6 pixels", has(problems, "size Tiny needs a width and height above 0"))
  check("t6 words", has(problems, "size Words needs x, y, w and h"))
  check("t6 thin", has(problems, "size Thin needs x, y, w and h"))
  check("t6 problem count", #problems == 8, tostring(#problems))
  check("t6 not a table", #A.sizes("junk") == 0)
  check("t6 label", A.label("size:Reading") == "Reading")
end

-- Test 7: A custom size shortcut beats a default and a malformed one is reported.
tests[#tests + 1] = function()
  local map, problems = A.shortcuts({}, {
    ["size:Reading"] = { mods = { "ctrl", "alt" }, key = "c" },
    ["size:Bad"] = { key = "b" },
  })
  check("t7 size wins", map["size:Reading"] ~= nil and map.center == nil)
  check("t7 said", has(problems, "size:Reading and center share ⌃⌥C: size:Reading keeps it"))
  check("t7 malformed", has(problems, "shortcut for size:Bad needs mods and key"))
  local keyed, none = A.shortcuts({ ["size:Plain"] = { mods = { "ctrl" }, key = "p" } },
    { ["size:Plain"] = false })
  check("t7 size without its own key", keyed["size:Plain"] ~= nil and #none == 0,
    table.concat(none, "; "))
end

-- Test 8: Spectacle's keymap binds its defaults, and an unknown keymap falls back to Rectangle's.
tests[#tests + 1] = function()
  local map, problems = A.shortcuts({}, {}, "spectacle")
  local n = 0
  for _ in pairs(map) do n = n + 1 end
  check("t8 count", n == 17, tostring(n))
  check("t8 clean", #problems == 0, table.concat(problems, "; "))
  check("t8 left", A.keyText(map["left-half"]) == "⌥⌘←")
  check("t8 next third", A.keyText(map["first-third"]) == "⌃⌥→")
  check("t8 previous third", A.keyText(map["last-third"]) == "⌃⌥←")
  check("t8 lower left", A.keyText(map["bottom-left"]) == "⌃⇧⌘←")
  check("t8 undo", A.keyText(map.restore) == "⌥⌘Z")
  check("t8 larger", A.keyText(map.larger) == "⌃⌥⇧→")
  for name in pairs(map) do
    check("t8 known " .. name, A.known(name))
  end
  local fallback = A.shortcuts({}, {}, "nope")
  check("t8 fallback", A.keyText(fallback["left-half"]) == "⌃⌥←")
  check("t8 names", table.concat(A.keymapNames, ",") == "rectangle,spectacle")
end

-- Test 9: Mouse buttons from 2 to 31 bind known actions and custom sizes, and the rest are
-- reported.
tests[#tests + 1] = function()
  local map, problems = A.mouseButtons({
    [3] = "maximize",
    [4] = "size:Reading",
    [31] = "next-display",
    [1] = "maximize",
    [32] = "maximize",
    [2] = "sideways",
    [5] = "size:Missing",
    side = "maximize",
    [2.5] = "maximize",
  }, { { name = "size:Reading" } })
  check("t9 kept", map[3] == "maximize" and map[4] == "size:Reading" and map[31] == "next-display")
  check("t9 primary", has(problems, "mouseButtons has button 1: use a number from 2 to 31"))
  check("t9 high", has(problems, "button 32"))
  check("t9 word", has(problems, "button side"))
  check("t9 fraction", has(problems, "button 2.5"))
  check("t9 unknown", has(problems, "unknown action sideways for button 2"))
  check("t9 missing size", has(problems, "unknown action size:Missing for button 5"))
  check("t9 count", #problems == 6, tostring(#problems))
  check("t9 not a table", next((A.mouseButtons("junk"))) == nil)
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
