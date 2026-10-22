-- tile_test checks the organize frame math in tile.lua, which runs without
-- Hammerspoon. Run it from the repo root with: lua tests/tile_test.lua

package.path = "./?.lua;" .. package.path

local T = require("tile")
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

-- show formats a frame for a failure message.
local function show(f)
  if not f then return "nil" end
  return string.format("{%g,%g,%g,%g}", f.x, f.y, f.w, f.h)
end

-- is checks that got equals want.
local function is(name, got, want)
  check(name, got ~= nil and got.x == want.x and got.y == want.y and got.w == want.w
    and got.h == want.h, "got " .. show(got) .. ", want " .. show(want))
end

-- covered returns the summed area of frames.
local function covered(frames)
  local total = 0
  for _, f in ipairs(frames) do total = total + f.w * f.h end
  return total
end

-- channel is the default channel of a 5120 by 1440 ultrawide.
local channel = { x = 512, y = 25, w = 2304, h = 1415 }

local tests = {}

-- Test 0: Columns and rows split the area evenly with no gap.
tests[#tests + 1] = function()
  local c = T.columns(channel, 3)
  is("t0 col 1", c[1], { x = 512, y = 25, w = 768, h = 1415 })
  is("t0 col 3", c[3], { x = 2048, y = 25, w = 768, h = 1415 })
  local r = T.rows(channel, 2)
  is("t0 row 1", r[1], { x = 512, y = 25, w = 2304, h = 707 })
  is("t0 row 2", r[2], { x = 512, y = 732, w = 2304, h = 708 })
  is("t0 one column", T.columns(channel, 1)[1], channel)
  check("t0 none", #T.columns(channel, 0) == 0)
end

-- Test 1: Columns with a gap leave the gap between and around them.
tests[#tests + 1] = function()
  local c = T.columns(channel, 2, 10)
  is("t1 left", c[1], { x = 522, y = 35, w = 1137, h = 1395 })
  check("t1 between", c[2].x - (c[1].x + c[1].w) == 10)
end

-- Test 2: The grid is near square and a short last row widens to leave no hole.
tests[#tests + 1] = function()
  for n = 1, 10 do
    check("t2 cover " .. n, covered(T.grid(channel, n)) == channel.w * channel.h,
      tostring(covered(T.grid(channel, n))))
  end
  local g = T.grid(channel, 3)
  is("t2 three a", g[1], { x = 512, y = 25, w = 1152, h = 707 })
  is("t2 three b", g[2], { x = 1664, y = 25, w = 1152, h = 707 })
  is("t2 three c", g[3], { x = 512, y = 732, w = 2304, h = 708 })
  local five = T.grid(channel, 5)
  is("t2 five d", five[4], { x = 512, y = 732, w = 1152, h = 708 })
  is("t2 single", T.grid(channel, 1)[1], channel)
end

-- Test 3: Cascade steps each window and keeps sizes that fit.
tests[#tests + 1] = function()
  local frames = T.cascade(channel, {
    { x = 0, y = 0, w = 800, h = 600 },
    { x = 0, y = 0, w = 900, h = 1415 },
    { x = 0, y = 0, w = 3000, h = 500 },
  }, 30)
  is("t3 first", frames[1], { x = 512, y = 25, w = 800, h = 600 })
  is("t3 second", frames[2], { x = 542, y = 55, w = 900, h = 1355 })
  is("t3 third", frames[3], { x = 572, y = 85, w = 2244, h = 500 })
  is("t3 single", T.cascade(channel, { { x = 9, y = 9, w = 800, h = 600 } }, 30)[1],
    { x = 512, y = 25, w = 800, h = 600 })
end

-- Test 4: Many windows shrink the step so the stack stays within half the area.
tests[#tests + 1] = function()
  local list = {}
  for i = 1, 60 do list[i] = { x = 0, y = 0, w = 500, h = 400 } end
  local frames = T.cascade(channel, list, 30)
  check("t4 step", frames[2].x - frames[1].x == 11, tostring(frames[2].x - frames[1].x))
  local last = frames[60]
  check("t4 inside", last.x + last.w <= channel.x + channel.w and last.y + last.h <= channel.y + channel.h,
    show(last))
end

-- Test 5: Reverse mirrors across the area and twice is the identity.
tests[#tests + 1] = function()
  local f = { x = 600, y = 100, w = 1000, h = 800 }
  is("t5 mirror", T.reverse(channel, f), { x = 1728, y = 100, w = 1000, h = 800 })
  is("t5 twice", T.reverse(channel, T.reverse(channel, f)), f)
  is("t5 half", T.reverse(channel, { x = 512, y = 25, w = 1152, h = 1415 }),
    { x = 1664, y = 25, w = 1152, h = 1415 })
end

-- Test 6: Every organize name is handled and others are not.
tests[#tests + 1] = function()
  for _, n in ipairs(T.names) do
    check("t6 " .. n, T.handles(n))
  end
  check("t6 count", #T.names == 8)
  check("t6 other", not T.handles("left-half"))
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
