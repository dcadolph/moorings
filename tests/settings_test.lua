-- settings_test checks the key recording and size parsing in settings.lua,
-- which run without Hammerspoon. Run it from the repo root with:
-- lua tests/settings_test.lua

package.path = "./?.lua;" .. package.path

local S = require("settings")
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

local tests = {}

-- Test 0: Browser key codes map to Hammerspoon key names.
tests[#tests + 1] = function()
  for code, want in pairs({
    KeyA = "a", KeyZ = "z", Digit0 = "0", Digit9 = "9", F1 = "f1", F12 = "f12", F20 = "f20",
    ArrowLeft = "left", ArrowDown = "down", Enter = "return", Backspace = "delete",
    Delete = "forwarddelete", Equal = "=", Minus = "-", Space = "space", Backslash = "\\",
    Backquote = "`", Slash = "/",
  }) do
    check("t0 " .. code, S.keyFromCode(code) == want, tostring(S.keyFromCode(code)))
  end
  for _, code in ipairs({ "F21", "F0", "Keya", "KeyAB", "IntlYen", "ShiftLeft", "", "Digit10" }) do
    check("t0 none " .. code, S.keyFromCode(code) == nil, tostring(S.keyFromCode(code)))
  end
  check("t0 not a string", S.keyFromCode(nil) == nil and S.keyFromCode(5) == nil)
end

-- Test 1: A recorded press becomes a shortcut, and a bare key or an unknown key is refused.
tests[#tests + 1] = function()
  local sc = S.shortcutFrom({ code = "KeyH", ctrl = true, alt = true, shift = true, cmd = true })
  check("t1 all mods", sc and table.concat(sc.mods, "+") == "ctrl+alt+shift+cmd" and sc.key == "h")
  sc = S.shortcutFrom({ code = "ArrowLeft", cmd = true })
  check("t1 cmd only", sc and table.concat(sc.mods, "+") == "cmd" and sc.key == "left")
  local none, why = S.shortcutFrom({ code = "KeyH" })
  check("t1 bare", none == nil and why == "Add Control, Option or Command to that key.")
  none, why = S.shortcutFrom({ code = "KeyH", shift = true })
  check("t1 shift only", none == nil and why ~= nil)
  sc = S.shortcutFrom({ code = "F5" })
  check("t1 function key", sc and #sc.mods == 0 and sc.key == "f5")
  none, why = S.shortcutFrom({ code = "IntlYen", ctrl = true })
  check("t1 unknown", none == nil and why == "That key cannot be bound.")
end

-- Test 2: Size fields from the window become numbers, blanks become nil, and the title is trimmed.
tests[#tests + 1] = function()
  local e = S.sizeFrom({ title = "  Reading ", x = "0.25", y = "", w = "0.5", h = nil, width = "1280",
    height = "abc" })
  check("t2 title", e.title == "Reading")
  check("t2 numbers", e.x == 0.25 and e.w == 0.5 and e.width == 1280)
  check("t2 blanks", e.y == nil and e.h == nil and e.height == nil)
  check("t2 no title", S.sizeFrom({ title = "   " }).title == nil and S.sizeFrom({}).title == nil)
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
