-- geometry holds the frame math moorings uses. Every function is pure: it takes
-- frames and numbers and returns new frames, so it runs without Hammerspoon.

local G = {}

-- edge returns the frame an edge of pct width occupies on f.
function G.edge(f, side, pct)
  local w = math.floor(f.w * pct / 100)
  if side == "right" then
    return { x = f.x + f.w - w, y = f.y, w = w, h = f.h }
  end
  return { x = f.x, y = f.y, w = w, h = f.h }
end

-- slot returns the frame a pin in row of side occupies on f at pct width. A nil
-- row fills the strip's full height. The bottom half takes the odd point.
function G.slot(f, side, row, pct)
  local r = G.edge(f, side, pct)
  local top = math.floor(f.h / 2)
  if row == "top" then
    r.h = top
  elseif row == "bottom" then
    r.y, r.h = f.y + top, f.h - top
  end
  return r
end

-- regions splits f into the left edge, the channel and the right edge.
function G.regions(f, leftPct, rightPct)
  local left = G.edge(f, "left", leftPct)
  local right = G.edge(f, "right", rightPct)
  return {
    left = left,
    channel = { x = left.x + left.w, y = f.y, w = right.x - left.x - left.w, h = f.h },
    right = right,
  }
end

-- clamp fits f inside ch, shrinking it only when it is larger than ch.
function G.clamp(f, ch)
  local w = math.min(f.w, ch.w)
  local h = math.min(f.h, ch.h)
  return {
    x = math.max(ch.x, math.min(f.x, ch.x + ch.w - w)),
    y = math.max(ch.y, math.min(f.y, ch.y + ch.h - h)),
    w = w,
    h = h,
  }
end

-- cell describes a grid position as columns c0 to c1 of nc and rows r0 to r1 of
-- nr. orient swaps the axes on a portrait area, so a first third is the left
-- column on a wide area and the top row on a tall one.
local function cell(c0, c1, nc, r0, r1, nr, orient)
  return { c0 = c0, c1 = c1, nc = nc, r0 = r0, r1 = r1, nr = nr, orient = orient }
end

-- cornerThird returns the landscape and portrait cells of a corner third, which
-- is two thirds wide and half tall on a wide area, and half wide and two thirds
-- tall on a tall one.
local function cornerThird(right, bottom)
  local c = right and { 1, 3 } or { 0, 2 }
  local r = bottom and { 1, 2 } or { 0, 1 }
  local pc = right and { 1, 2 } or { 0, 1 }
  local pr = bottom and { 1, 3 } or { 0, 2 }
  return {
    landscape = cell(c[1], c[2], 3, r[1], r[2], 2),
    portrait = cell(pc[1], pc[2], 2, pr[1], pr[2], 3),
  }
end

-- cells maps each grid action name to its cell. The names match Rectangle's.
G.cells = {
  ["left-half"] = cell(0, 1, 2, 0, 1, 1),
  ["right-half"] = cell(1, 2, 2, 0, 1, 1),
  ["center-half"] = cell(1, 3, 4, 0, 1, 1),
  ["top-half"] = cell(0, 1, 1, 0, 1, 2),
  ["bottom-half"] = cell(0, 1, 1, 1, 2, 2),
  ["top-left"] = cell(0, 1, 2, 0, 1, 2),
  ["top-right"] = cell(1, 2, 2, 0, 1, 2),
  ["bottom-left"] = cell(0, 1, 2, 1, 2, 2),
  ["bottom-right"] = cell(1, 2, 2, 1, 2, 2),
  ["first-third"] = cell(0, 1, 3, 0, 1, 1, true),
  ["center-third"] = cell(1, 2, 3, 0, 1, 1, true),
  ["last-third"] = cell(2, 3, 3, 0, 1, 1, true),
  ["first-two-thirds"] = cell(0, 2, 3, 0, 1, 1, true),
  ["center-two-thirds"] = cell(1, 5, 6, 0, 1, 1, true),
  ["last-two-thirds"] = cell(1, 3, 3, 0, 1, 1, true),
  ["first-fourth"] = cell(0, 1, 4, 0, 1, 1, true),
  ["second-fourth"] = cell(1, 2, 4, 0, 1, 1, true),
  ["third-fourth"] = cell(2, 3, 4, 0, 1, 1, true),
  ["last-fourth"] = cell(3, 4, 4, 0, 1, 1, true),
  ["first-three-fourths"] = cell(0, 3, 4, 0, 1, 1, true),
  ["center-three-fourths"] = cell(1, 7, 8, 0, 1, 1, true),
  ["last-three-fourths"] = cell(1, 4, 4, 0, 1, 1, true),
  ["top-left-third"] = cornerThird(false, false),
  ["top-right-third"] = cornerThird(true, false),
  ["bottom-left-third"] = cornerThird(false, true),
  ["bottom-right-third"] = cornerThird(true, true),
}

-- grid adds a cell for every square of an nc by nr grid, named by rowNames and
-- colNames joined with a hyphen and the suffix, and returns the names in
-- reading order.
local function grid(nc, nr, colNames, rowNames, suffix)
  local names = {}
  for r, rowName in ipairs(rowNames) do
    for c, colName in ipairs(colNames) do
      local name = rowName .. "-" .. colName .. "-" .. suffix
      G.cells[name] = cell(c - 1, c, nc, r - 1, r, nr)
      names[#names + 1] = name
    end
  end
  return names
end

-- grids lists the grid position names by family, in reading order.
G.grids = {
  sixths = grid(3, 2, { "left", "center", "right" }, { "top", "bottom" }, "sixth"),
  ninths = grid(3, 3, { "left", "center", "right" }, { "top", "middle", "bottom" }, "ninth"),
  eighths = grid(4, 2, { "left", "center-left", "center-right", "right" }, { "top", "bottom" },
    "eighth"),
  cornerThirds = { "top-left-third", "top-right-third", "bottom-left-third", "bottom-right-third" },
}

-- span returns the start and length of parts i0 to i1 of n across length at
-- origin, with the outer gap at the area's edges and half the gap between parts.
local function span(origin, length, i0, i1, n, gap)
  local a = origin + math.floor(length * i0 / n)
  local b = origin + math.floor(length * i1 / n)
  local half = math.floor(gap / 2)
  a = a + (i0 == 0 and gap or gap - half)
  b = b - (i1 == n and gap or half)
  return a, b - a
end

-- inset shrinks f by gap on every side.
local function inset(f, gap)
  return { x = f.x + gap, y = f.y + gap, w = f.w - 2 * gap, h = f.h - 2 * gap }
end

-- fromCell returns the frame of c inside area, honoring orientation and gap.
local function fromCell(c, area, gap)
  local portrait = area.h > area.w
  if c.landscape then
    c = portrait and c.portrait or c.landscape
  elseif c.orient and portrait then
    c = cell(c.r0, c.r1, c.nr, c.c0, c.c1, c.nc)
  end
  local x, w = span(area.x, area.w, c.c0, c.c1, c.nc, gap)
  local y, h = span(area.y, area.h, c.r0, c.r1, c.nr, gap)
  return { x = x, y = y, w = w, h = h }
end

-- round returns n rounded to the nearest whole point.
local function round(n)
  return math.floor(n + 0.5)
end

-- center returns cur centered in area, filling an axis it is too large for.
local function center(area, cur)
  local f = { x = cur.x, y = cur.y, w = cur.w, h = cur.h }
  if f.w > area.w then
    f.x, f.w = area.x, area.w
  else
    f.x = area.x + round((area.w - f.w) / 2)
  end
  if f.h > area.h then
    f.y, f.h = area.y, area.h
  else
    f.y = area.y + round((area.h - f.h) / 2)
  end
  return f
end

-- slide returns cur pushed against one edge of area, centered on the other axis.
local function slide(area, cur, dir)
  local f = center(area, cur)
  if dir == "left" then
    f.x = area.x
  elseif dir == "right" then
    f.x = area.x + area.w - f.w
  elseif dir == "up" then
    f.y = area.y
  else
    f.y = area.y + area.h - f.h
  end
  return f
end

-- almost is the share of the area almost-maximize fills on each axis.
local almost = 0.9

-- relative maps each action that depends on the window's own frame to the
-- function that computes it from the work area, the current frame and the gap.
local relative = {
  maximize = function(area, _, gap)
    return inset(area, gap)
  end,
  ["almost-maximize"] = function(area)
    local w, h = round(area.w * almost), round(area.h * almost)
    return { x = area.x + round((area.w - w) / 2), y = area.y + round((area.h - h) / 2), w = w, h = h }
  end,
  ["maximize-height"] = function(area, cur, gap)
    return { x = cur.x, y = area.y + gap, w = cur.w, h = area.h - 2 * gap }
  end,
  center = function(area, cur, gap)
    return center(inset(area, gap), cur)
  end,
  ["center-prominently"] = function(area, cur, gap)
    local a = inset(area, gap)
    local f = center(a, cur)
    f.y = f.y - round((a.h - f.h) / 4)
    return f
  end,
  ["move-left"] = function(area, cur, gap)
    return slide(inset(area, gap), cur, "left")
  end,
  ["move-right"] = function(area, cur, gap)
    return slide(inset(area, gap), cur, "right")
  end,
  ["move-up"] = function(area, cur, gap)
    return slide(inset(area, gap), cur, "up")
  end,
  ["move-down"] = function(area, cur, gap)
    return slide(inset(area, gap), cur, "down")
  end,
}

-- position returns the frame action name gives a window at cur inside area,
-- leaving gap points around and between windows. It returns nil for a name it
-- does not know.
function G.position(name, area, cur, gap)
  gap = gap or 0
  local c = G.cells[name]
  if c then
    return fromCell(c, area, gap)
  end
  local fn = relative[name]
  if fn then
    return fn(area, cur or area, gap)
  end
  return nil
end

-- cycles maps each action that changes on a repeat press to the positions it
-- steps through. A table entry is a cell that ignores orientation, so a half
-- cycles its width on a tall area as well.
G.cycles = {
  ["left-half"] = { "left-half", cell(0, 2, 3, 0, 1, 1), cell(0, 1, 3, 0, 1, 1) },
  ["right-half"] = { "right-half", cell(1, 3, 3, 0, 1, 1), cell(2, 3, 3, 0, 1, 1) },
  ["first-third"] = { "first-third", "center-third", "last-third" },
  ["last-third"] = { "last-third", "center-third", "first-third" },
}

-- cycle returns the frame of press i of action name, wrapping after the last
-- step. A name without a cycle returns its plain position.
function G.cycle(name, i, area, cur, gap)
  local steps = G.cycles[name]
  if not steps then
    return G.position(name, area, cur, gap)
  end
  local s = steps[(i - 1) % #steps + 1]
  if type(s) == "string" then
    return G.position(s, area, cur, gap)
  end
  return fromCell(s, area, gap or 0)
end

-- minShare is the smallest share of the area smaller will shrink an axis to.
local minShare = 0.25

-- touch is how many points from an area edge still count as touching it.
local touch = 2

-- grow moves the free edges of the span lo to lo+len by d within alo to
-- alo+alen. An edge touching the area stays put, like a curtain. When
-- shrinking a span that touches both edges, both edges move in.
local function grow(lo, len, alo, alen, d)
  local hi, ahi = lo + len, alo + alen
  local atLo, atHi = lo <= alo + touch, hi >= ahi - touch
  if d < 0 and atLo and atHi then
    atLo, atHi = false, false
  end
  local nlo = atLo and lo or math.max(alo, lo - d)
  local nhi = atHi and hi or math.min(ahi, hi + d)
  if d < 0 and nhi - nlo < alen * minShare then
    return lo, len
  end
  return nlo, nhi - nlo
end

-- resize grows cur by d points on each free edge inside area, or shrinks it
-- when d is negative. cur is first clamped into the area.
function G.resize(area, cur, d, gap)
  local a = inset(area, gap or 0)
  local f = G.clamp(cur, a)
  local x, w = grow(f.x, f.w, a.x, a.w, d)
  local y, h = grow(f.y, f.h, a.y, a.h, d)
  return { x = x, y = y, w = w, h = h }
end

-- transfer maps cur from one area to another, keeping its relative position
-- and size, so a left half stays a left half on the next display.
function G.transfer(cur, from, to)
  local sx, sy = to.w / from.w, to.h / from.h
  local f = {
    x = to.x + round((cur.x - from.x) * sx),
    y = to.y + round((cur.y - from.y) * sy),
    w = round(cur.w * sx),
    h = round(cur.h * sy),
  }
  return G.clamp(f, to)
end

-- fspan returns the start and length of the share f0 to f1 of length at origin,
-- with the outer gap at the area's edges and half the gap between neighbors.
-- It floors like span, with a little slack so a share such as 2/3 does not
-- lose a point to float error.
local function fspan(origin, length, f0, f1, gap)
  local a = origin + math.floor(length * f0 + 1e-9)
  local b = origin + math.floor(length * f1 + 1e-9)
  local half = math.floor(gap / 2)
  a = a + (f0 < 1e-9 and gap or gap - half)
  b = b - (f1 > 1 - 1e-9 and gap or half)
  return a, b - a
end

-- custom returns the frame of a custom size inside area. spec holds x, y, w and
-- h as shares of the area, and an optional width and height in points that
-- center a window of that size in the share, shrunk to fit when larger.
function G.custom(area, spec, gap)
  gap = gap or 0
  local x, w = fspan(area.x, area.w, spec.x or 0, (spec.x or 0) + (spec.w or 1), gap)
  local y, h = fspan(area.y, area.h, spec.y or 0, (spec.y or 0) + (spec.h or 1), gap)
  if spec.width and spec.width < w then
    x, w = x + round((w - spec.width) / 2), spec.width
  end
  if spec.height and spec.height < h then
    y, h = y + round((h - spec.height) / 2), spec.height
  end
  return { x = x, y = y, w = w, h = h }
end

-- names returns every action position knows, sorted.
function G.names()
  local list = {}
  for name in pairs(G.cells) do
    list[#list + 1] = name
  end
  for name in pairs(relative) do
    list[#list + 1] = name
  end
  table.sort(list)
  return list
end

return G
