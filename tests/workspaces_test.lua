-- workspaces_test checks the display signature and window matching in
-- workspaces.lua, which run without Hammerspoon. Run it from the repo root with:
-- lua tests/workspaces_test.lua

package.path = "./?.lua;" .. package.path

local W = require("workspaces")
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

-- Test 0: The signature names every screen and ignores their order.
tests[#tests + 1] = function()
  local wide = { x = 0, y = 0, w = 5120, h = 1440 }
  local side = { x = 5120, y = 0, w = 1512, h = 982 }
  local a = W.signature({ wide, side })
  check("t0 order", a == W.signature({ side, wide }), a)
  check("t0 text", a == "1512x982@5120,0 5120x1440@0,0", a)
  check("t0 position", a ~= W.signature({ wide, { x = -1512, y = 0, w = 1512, h = 982 } }))
  check("t0 one", W.signature({ wide }) ~= a)
  check("t0 none", W.signature({}) == "")
end

-- Test 1: Matching prefers a title match, then any unused window of the app.
tests[#tests + 1] = function()
  local saved = {
    { bundle = "safari", title = "Mail" },
    { bundle = "safari", title = "Docs" },
    { bundle = "notes", title = "Notes" },
    { bundle = "safari", title = "Gone" },
  }
  local live = {
    { bundle = "safari", title = "Docs" },
    { bundle = "safari", title = "Renamed" },
    { bundle = "chrome", title = "Mail" },
  }
  local m = W.match(saved, live)
  check("t1 docs by title", m[2] == 1, tostring(m[2]))
  check("t1 mail by app", m[1] == 2, tostring(m[1]))
  check("t1 notes missing", m[3] == nil)
  check("t1 extra missing", m[4] == nil)
  local twice = W.match({ { bundle = "a", title = "x" } }, { { bundle = "b", title = "x" } })
  check("t1 title needs app", twice[1] == nil)
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
