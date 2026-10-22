-- geometry_test checks the pure frame math in geometry.lua. Run it from the
-- repo root with: lua tests/geometry_test.lua

package.path = "./?.lua;" .. package.path

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

-- inside reports whether f lies within area.
local function inside(f, area)
  return f.x >= area.x and f.y >= area.y and f.w > 0 and f.h > 0
    and f.x + f.w <= area.x + area.w and f.y + f.h <= area.y + area.h
end

-- channel is the default channel of a 5120 by 1440 ultrawide.
local channel = { x = 512, y = 25, w = 2304, h = 1415 }

-- tall is a portrait area.
local tall = { x = 0, y = 25, w = 1080, h = 1895 }

-- window is a frame that fits inside channel.
local window = { x = 600, y = 100, w = 1000, h = 800 }

local tests = {}

-- Test 0: Halves split the area exactly with no gap.
tests[#tests + 1] = function()
  is("t0 left", G.position("left-half", channel), { x = 512, y = 25, w = 1152, h = 1415 })
  is("t0 right", G.position("right-half", channel), { x = 1664, y = 25, w = 1152, h = 1415 })
  is("t0 top", G.position("top-half", channel), { x = 512, y = 25, w = 2304, h = 707 })
  is("t0 bottom", G.position("bottom-half", channel), { x = 512, y = 732, w = 2304, h = 708 })
  is("t0 center", G.position("center-half", channel), { x = 1088, y = 25, w = 1152, h = 1415 })
end

-- Test 1: Quarters sit in their corners.
tests[#tests + 1] = function()
  is("t1 tl", G.position("top-left", channel), { x = 512, y = 25, w = 1152, h = 707 })
  is("t1 br", G.position("bottom-right", channel), { x = 1664, y = 732, w = 1152, h = 708 })
end

-- Test 2: Thirds and two thirds tile the width on a wide area.
tests[#tests + 1] = function()
  local a = G.position("first-third", channel)
  local b = G.position("center-third", channel)
  local c = G.position("last-third", channel)
  is("t2 first", a, { x = 512, y = 25, w = 768, h = 1415 })
  check("t2 tile ab", a.x + a.w == b.x)
  check("t2 tile bc", b.x + b.w == c.x)
  check("t2 tile end", c.x + c.w == channel.x + channel.w)
  is("t2 first two", G.position("first-two-thirds", channel), { x = 512, y = 25, w = 1536, h = 1415 })
  is("t2 last two", G.position("last-two-thirds", channel), { x = 1280, y = 25, w = 1536, h = 1415 })
  is("t2 center two", G.position("center-two-thirds", channel), { x = 896, y = 25, w = 1536, h = 1415 })
end

-- Test 3: Thirds and fourths turn into rows on a portrait area.
tests[#tests + 1] = function()
  is("t3 first third", G.position("first-third", tall), { x = 0, y = 25, w = 1080, h = 631 })
  is("t3 last fourth", G.position("last-fourth", tall), { x = 0, y = 1446, w = 1080, h = 474 })
  is("t3 halves stay", G.position("left-half", tall), { x = 0, y = 25, w = 540, h = 1895 })
end

-- Test 4: Corner thirds are two thirds wide on a wide area and two thirds tall on a tall one.
tests[#tests + 1] = function()
  is("t4 tl wide", G.position("top-left-third", channel), { x = 512, y = 25, w = 1536, h = 707 })
  is("t4 br wide", G.position("bottom-right-third", channel), { x = 1280, y = 732, w = 1536, h = 708 })
  is("t4 tr tall", G.position("top-right-third", tall), { x = 540, y = 25, w = 540, h = 1263 })
  is("t4 bl tall", G.position("bottom-left-third", tall), { x = 0, y = 656, w = 540, h = 1264 })
end

-- Test 5: Fourths tile the width and three fourths cover the right span.
tests[#tests + 1] = function()
  local x = channel.x
  for _, name in ipairs({ "first-fourth", "second-fourth", "third-fourth", "last-fourth" }) do
    local f = G.position(name, channel)
    check("t5 " .. name, f.x == x and f.w == 576, show(f))
    x = f.x + f.w
  end
  is("t5 first three", G.position("first-three-fourths", channel), { x = 512, y = 25, w = 1728, h = 1415 })
  is("t5 last three", G.position("last-three-fourths", channel), { x = 1088, y = 25, w = 1728, h = 1415 })
  is("t5 center three", G.position("center-three-fourths", channel), { x = 800, y = 25, w = 1728, h = 1415 })
end

-- Test 6: Sixths, ninths and eighths cover the area with no overlap.
tests[#tests + 1] = function()
  for _, suffix in ipairs({ "sixth", "ninth", "eighth" }) do
    local total, count = 0, 0
    for _, name in ipairs(G.names()) do
      if name:sub(-#suffix - 1) == "-" .. suffix then
        local f = G.position(name, channel)
        check("t6 inside " .. name, inside(f, channel), show(f))
        total, count = total + f.w * f.h, count + 1
      end
    end
    local want = ({ sixth = 6, ninth = 9, eighth = 8 })[suffix]
    check("t6 count " .. suffix, count == want, tostring(count))
    check("t6 area " .. suffix, total == channel.w * channel.h, tostring(total))
  end
  is("t6 middle center ninth", G.position("middle-center-ninth", channel),
    { x = 1280, y = 496, w = 768, h = 472 })
  is("t6 top center-right eighth", G.position("top-center-right-eighth", channel),
    { x = 1664, y = 25, w = 576, h = 707 })
end

-- Test 7: A gap insets the area edges by the gap and leaves the gap between neighbors.
tests[#tests + 1] = function()
  local l = G.position("left-half", channel, nil, 10)
  local r = G.position("right-half", channel, nil, 10)
  is("t7 left", l, { x = 522, y = 35, w = 1137, h = 1395 })
  is("t7 right", r, { x = 1669, y = 35, w = 1137, h = 1395 })
  check("t7 between", r.x - (l.x + l.w) == 10)
  check("t7 edge", channel.x + channel.w - (r.x + r.w) == 10)
  local odd = G.position("right-half", channel, nil, 7)
  local oddL = G.position("left-half", channel, nil, 7)
  check("t7 odd between", odd.x - (oddL.x + oddL.w) == 7)
  is("t7 maximize", G.position("maximize", channel, window, 10), { x = 522, y = 35, w = 2284, h = 1395 })
end

-- Test 8: Maximize, almost maximize and maximize height.
tests[#tests + 1] = function()
  is("t8 max", G.position("maximize", channel, window), channel)
  is("t8 almost", G.position("almost-maximize", channel, window), { x = 627, y = 96, w = 2074, h = 1274 })
  is("t8 height", G.position("maximize-height", channel, window), { x = 600, y = 25, w = 1000, h = 1415 })
  is("t8 height gap", G.position("maximize-height", channel, window, 10),
    { x = 600, y = 35, w = 1000, h = 1395 })
end

-- Test 9: Center keeps the size, and an oversized axis fills the area.
tests[#tests + 1] = function()
  is("t9 center", G.position("center", channel, window), { x = 1164, y = 333, w = 1000, h = 800 })
  is("t9 wide", G.position("center", channel, { x = 0, y = 0, w = 3000, h = 800 }),
    { x = 512, y = 333, w = 2304, h = 800 })
  is("t9 tall", G.position("center", channel, { x = 0, y = 0, w = 1000, h = 2000 }),
    { x = 1164, y = 25, w = 1000, h = 1415 })
end

-- Test 10: Center prominently sits a quarter of the spare height above center.
tests[#tests + 1] = function()
  is("t10 prominent", G.position("center-prominently", channel, window),
    { x = 1164, y = 179, w = 1000, h = 800 })
end

-- Test 11: Moves push the window to an edge without resizing and center the other axis.
tests[#tests + 1] = function()
  is("t11 left", G.position("move-left", channel, window), { x = 512, y = 333, w = 1000, h = 800 })
  is("t11 right", G.position("move-right", channel, window), { x = 1816, y = 333, w = 1000, h = 800 })
  is("t11 up", G.position("move-up", channel, window), { x = 1164, y = 25, w = 1000, h = 800 })
  is("t11 down", G.position("move-down", channel, window), { x = 1164, y = 640, w = 1000, h = 800 })
end

-- Test 12: Every name returns a frame inside the area, and unknown names return nil.
tests[#tests + 1] = function()
  for _, name in ipairs(G.names()) do
    local f = G.position(name, channel, window)
    check("t12 " .. name, f ~= nil and inside(f, channel), show(f))
  end
  check("t12 unknown", G.position("sideways", channel, window) == nil)
  check("t12 count", #G.names() == 58, tostring(#G.names()))
end

-- Test 13: Edge, slot, regions and clamp keep their v2 results.
tests[#tests + 1] = function()
  local screen = { x = 0, y = 25, w = 5120, h = 1415 }
  is("t13 edge", G.edge(screen, "right", 45), { x = 2816, y = 25, w = 2304, h = 1415 })
  is("t13 slot", G.slot(screen, "left", "bottom", 10), { x = 0, y = 732, w = 512, h = 708 })
  is("t13 channel", G.regions(screen, 10, 45).channel, channel)
  is("t13 clamp", G.clamp({ x = 0, y = 0, w = 3000, h = 500 }, channel), { x = 512, y = 25, w = 2304, h = 500 })
end

-- Test 14: Halves cycle their width 1/2, 2/3, 1/3 and wrap, and thirds walk the area.
tests[#tests + 1] = function()
  local half = { x = 512, y = 25, w = 1152, h = 1415 }
  is("t14 left 1", G.cycle("left-half", 1, channel), half)
  is("t14 left 2", G.cycle("left-half", 2, channel), { x = 512, y = 25, w = 1536, h = 1415 })
  is("t14 left 3", G.cycle("left-half", 3, channel), { x = 512, y = 25, w = 768, h = 1415 })
  is("t14 left 4", G.cycle("left-half", 4, channel), half)
  is("t14 right 2", G.cycle("right-half", 2, channel), { x = 1280, y = 25, w = 1536, h = 1415 })
  is("t14 right 3", G.cycle("right-half", 3, channel), { x = 2048, y = 25, w = 768, h = 1415 })
  is("t14 first 2", G.cycle("first-third", 2, channel), G.position("center-third", channel))
  is("t14 first 3", G.cycle("first-third", 3, channel), G.position("last-third", channel))
  is("t14 last 2", G.cycle("last-third", 2, channel), G.position("center-third", channel))
  is("t14 last 3", G.cycle("last-third", 3, channel), G.position("first-third", channel))
  is("t14 tall half stays a width", G.cycle("left-half", 2, tall), { x = 0, y = 25, w = 720, h = 1895 })
  is("t14 no cycle", G.cycle("maximize", 5, channel, window), channel)
  check("t14 unknown", G.cycle("sideways", 1, channel, window) == nil)
end

-- Test 15: Larger and smaller move free edges by the step and hold edges at the area.
tests[#tests + 1] = function()
  is("t15 larger", G.resize(channel, window, 30), { x = 570, y = 70, w = 1060, h = 860 })
  is("t15 smaller", G.resize(channel, window, -30), { x = 630, y = 130, w = 940, h = 740 })
  local half = G.position("left-half", channel)
  is("t15 larger curtain", G.resize(channel, half, 30), { x = 512, y = 25, w = 1182, h = 1415 })
  is("t15 smaller curtain", G.resize(channel, half, -30), { x = 512, y = 55, w = 1122, h = 1355 })
  is("t15 smaller full", G.resize(channel, channel, -30), { x = 542, y = 55, w = 2244, h = 1355 })
  is("t15 larger full", G.resize(channel, channel, 30), channel)
  is("t15 larger stops at edge", G.resize(channel, { x = 530, y = 100, w = 1000, h = 800 }, 30),
    { x = 512, y = 70, w = 1048, h = 860 })
  is("t15 smaller floor", G.resize(channel, { x = 600, y = 100, w = 600, h = 800 }, -30),
    { x = 600, y = 130, w = 600, h = 740 })
  is("t15 clamped first", G.resize(channel, { x = 0, y = 0, w = 3000, h = 500 }, 30),
    { x = 512, y = 25, w = 2304, h = 530 })
end

-- Test 16: Transfer keeps the relative frame across areas of different sizes.
tests[#tests + 1] = function()
  local laptop = { x = 5120, y = 25, w = 1512, h = 957 }
  local half = G.position("left-half", channel)
  local moved = G.transfer(half, channel, laptop)
  is("t16 to laptop", moved, { x = 5120, y = 25, w = 756, h = 957 })
  is("t16 and back", G.transfer(moved, laptop, channel), half)
  is("t16 right half", G.transfer(G.position("right-half", channel), channel, laptop),
    { x = 5876, y = 25, w = 756, h = 957 })
  check("t16 inside", inside(G.transfer({ x = 2000, y = 900, w = 900, h = 600 }, channel, laptop),
    laptop))
end

-- Test 17: The grid families list every grid name once, in reading order.
tests[#tests + 1] = function()
  check("t17 sixths", table.concat(G.grids.sixths, ",") == "top-left-sixth,top-center-sixth,"
    .. "top-right-sixth,bottom-left-sixth,bottom-center-sixth,bottom-right-sixth",
    table.concat(G.grids.sixths, ","))
  check("t17 counts", #G.grids.ninths == 9 and #G.grids.eighths == 8 and #G.grids.cornerThirds == 4)
  for _, list in pairs(G.grids) do
    for _, name in ipairs(list) do
      check("t17 known " .. name, G.position(name, channel) ~= nil)
    end
  end
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
