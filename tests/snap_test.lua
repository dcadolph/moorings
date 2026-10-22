-- snap_test checks the drag zones in snap.lua, which run without Hammerspoon.
-- Run it from the repo root with: lua tests/snap_test.lua

package.path = "./?.lua;" .. package.path

local S = require("snap")
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

-- zoneIs checks the zone at x, y on f with channel ch and previous zone prev.
local function zoneIs(name, f, ch, x, y, want, prev)
  local got = S.zone({ x = x, y = y }, f, ch, prev)
  check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

-- screen is a 1920 by 1080 display at the origin.
local screen = { x = 0, y = 0, w = 1920, h = 1080 }

-- side is a display to the right of an ultrawide.
local side = { x = 5120, y = 0, w = 1512, h = 982 }

-- wide is a 5120 by 1440 ultrawide and ch its default channel.
local wide = { x = 0, y = 0, w = 5120, h = 1440 }
local ch = { x = 512, y = 25, w = 2304, h = 1415 }

local tests = {}

-- Test 0: Left and right edges give halves, near corners give quarters, and near-corner
-- stretches give top and bottom halves.
tests[#tests + 1] = function()
  zoneIs("t0 left", screen, nil, 0, 540, "left-half")
  zoneIs("t0 left margin", screen, nil, 4, 540, "left-half")
  zoneIs("t0 past margin", screen, nil, 5, 540, nil)
  zoneIs("t0 right", screen, nil, 1919, 540, "right-half")
  zoneIs("t0 right margin", screen, nil, 1915, 540, "right-half")
  zoneIs("t0 right past", screen, nil, 1914, 540, nil)
  zoneIs("t0 left top corner", screen, nil, 0, 19, "top-left")
  zoneIs("t0 left top short", screen, nil, 0, 20, "top-half")
  zoneIs("t0 left short end", screen, nil, 0, 145, "left-half")
  zoneIs("t0 left bottom corner", screen, nil, 0, 1060, "bottom-left")
  zoneIs("t0 left bottom short", screen, nil, 0, 1000, "bottom-half")
  zoneIs("t0 right top corner", screen, nil, 1919, 5, "top-right")
  zoneIs("t0 right bottom corner", screen, nil, 1919, 1075, "bottom-right")
end

-- Test 1: The top edge maximizes, with corners and short stretches at its ends.
tests[#tests + 1] = function()
  zoneIs("t1 top", screen, nil, 960, 0, "maximize")
  zoneIs("t1 top margin", screen, nil, 960, 4, "maximize")
  zoneIs("t1 below", screen, nil, 960, 5, nil)
  zoneIs("t1 top left corner", screen, nil, 19, 0, "top-left")
  zoneIs("t1 top right corner", screen, nil, 1900, 0, "top-right")
  zoneIs("t1 top short", screen, nil, 100, 0, "top-half")
  zoneIs("t1 top short right", screen, nil, 1800, 0, "top-half")
end

-- Test 2: The bottom edge gives thirds, and the center turns to two thirds coming from a side.
tests[#tests + 1] = function()
  zoneIs("t2 first", screen, nil, 400, 1079, "first-third")
  zoneIs("t2 center", screen, nil, 960, 1079, "center-third")
  zoneIs("t2 last", screen, nil, 1500, 1079, "last-third")
  zoneIs("t2 from first", screen, nil, 960, 1079, "first-two-thirds", "first-third")
  zoneIs("t2 stays two", screen, nil, 960, 1079, "first-two-thirds", "first-two-thirds")
  zoneIs("t2 from last", screen, nil, 960, 1079, "last-two-thirds", "last-third")
  zoneIs("t2 from last two", screen, nil, 960, 1079, "last-two-thirds", "last-two-thirds")
  zoneIs("t2 other prev", screen, nil, 960, 1079, "center-third", "maximize")
  zoneIs("t2 bottom corner", screen, nil, 10, 1079, "bottom-left")
  zoneIs("t2 bottom short", screen, nil, 1800, 1079, "bottom-half")
  zoneIs("t2 above", screen, nil, 960, 1074, nil)
  zoneIs("t2 middle", screen, nil, 960, 540, nil)
end

-- Test 3: A display away from the origin measures from its own edges.
tests[#tests + 1] = function()
  zoneIs("t3 left", side, nil, 5120, 400, "left-half")
  zoneIs("t3 right", side, nil, 6631, 400, "right-half")
  zoneIs("t3 top", side, nil, 5900, 0, "maximize")
  zoneIs("t3 not left", side, nil, 5200, 400, nil)
  zoneIs("t3 bottom first", side, nil, 5300, 981, "first-third")
  zoneIs("t3 bottom last", side, nil, 6400, 981, "last-third")
end

-- Test 4: On the ultrawide the strips stand in for the edges and the channel keeps top and bottom.
tests[#tests + 1] = function()
  zoneIs("t4 left strip", wide, ch, 200, 700, "left-half")
  zoneIs("t4 left strip edge", wide, ch, 511, 700, "left-half")
  zoneIs("t4 channel start", wide, ch, 512, 700, nil)
  zoneIs("t4 left strip top", wide, ch, 200, 50, "top-left")
  zoneIs("t4 left strip bottom", wide, ch, 200, 1400, "bottom-left")
  zoneIs("t4 right strip", wide, ch, 4000, 700, "right-half")
  zoneIs("t4 right strip start", wide, ch, 2816, 700, "right-half")
  zoneIs("t4 channel end", wide, ch, 2815, 700, nil)
  zoneIs("t4 right strip top", wide, ch, 4000, 30, "top-right")
  zoneIs("t4 right strip bottom", wide, ch, 5119, 1439, "bottom-right")
  zoneIs("t4 top", wide, ch, 1500, 2, "maximize")
  zoneIs("t4 bottom first", wide, ch, 1000, 1439, "first-third")
  zoneIs("t4 bottom center", wide, ch, 1500, 1439, "center-third")
  zoneIs("t4 bottom last", wide, ch, 2500, 1439, "last-third")
  zoneIs("t4 bottom two", wide, ch, 1500, 1439, "last-two-thirds", "last-third")
  zoneIs("t4 middle", wide, ch, 1500, 700, nil)
end

-- Test 5: Park finds the strip half under the cursor and nothing over the channel.
tests[#tests + 1] = function()
  check("t5 left top", S.park({ x = 100, y = 100 }, wide, ch) == "left-top")
  check("t5 left bottom", S.park({ x = 511, y = 720 }, wide, ch) == "left-bottom")
  check("t5 right top", S.park({ x = 2816, y = 719 }, wide, ch) == "right-top")
  check("t5 right bottom", S.park({ x = 5119, y = 1439 }, wide, ch) == "right-bottom")
  check("t5 channel", S.park({ x = 512, y = 100 }, wide, ch) == nil)
  check("t5 channel end", S.park({ x = 2815, y = 100 }, wide, ch) == nil)
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
