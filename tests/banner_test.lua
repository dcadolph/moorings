-- banner_test drives banner.lua against a fake Hammerspoon canvas, timer and screen. Run it
-- from the repo root with: lua tests/banner_test.lua

package.path = "./?.lua;" .. package.path

local failures, passes = 0, 0
local world, B

-- check records a failure when cond is false.
local function check(name, cond, msg)
  if cond then
    passes = passes + 1
  else
    failures = failures + 1
    print("FAIL " .. name .. ": " .. (msg or "condition false"))
  end
end

-- install builds a fresh fake Hammerspoon in style and loads banner into it.
local function install(style)
  world = { style = style, canvases = {}, timers = {}, urls = {} }
  hs = {
    host = { interfaceStyle = function() return world.style end },
    screen = {
      primaryScreen = function()
        return { frame = function() return { x = 0, y = 25, w = 5120, h = 1415 } end }
      end,
    },
    styledtext = { new = function(text, attrs) return { text = text, attrs = attrs } end },
    base64 = { encode = function(s) return "<" .. s .. ">" end },
    image = {
      imageFromURL = function(url)
        world.urls[#world.urls + 1] = url
        return { url = url }
      end,
    },
    timer = {
      doAfter = function(seconds, fn)
        local t = { seconds = seconds, fn = fn }
        function t:stop() self.stopped = true end
        function t:fire() if not self.stopped then self.fn() end end
        world.timers[#world.timers + 1] = t
        return t
      end,
    },
    canvas = {
      new = function(frame)
        local c = { f = frame, elements = {} }
        function c:appendElements(...)
          for _, e in ipairs({ ... }) do self.elements[#self.elements + 1] = e end
          return self
        end
        function c:behaviorAsLabels(l) self.behavior = l return self end
        function c:level(l) self.lvl = l return self end
        function c:canvasMouseEvents(down, up, enterExit, move)
          self.mouse = { down = down, up = up, enterExit = enterExit, move = move }
          return self
        end
        function c:mouseCallback(fn) self.onMouse = fn return self end
        function c:show(fade) self.shown, self.showFade = true, fade return self end
        function c:delete(...)
          -- Hammerspoon rejects an explicit nil fade time, so the fake does too.
          if select("#", ...) > 0 and type(...) ~= "number" then
            error("incorrect type for argument 2 (expected number)")
          end
          local fade = ...
          self.deletes = (self.deletes or 0) + 1
          self.deleted, self.deleteFade = true, fade
        end
        world.canvases[#world.canvases + 1] = c
        return c
      end,
    },
  }
  package.loaded.banner = nil
  B = require("banner")
  B.markPath = "banner-mark.svg"
end

-- element returns the first element of canvas c whose type is kind, or nil.
local function element(c, kind)
  for _, e in ipairs(c.elements) do
    if e.type == kind then return e end
  end
end

-- texts returns the title and body strings drawn on canvas c.
local function texts(c)
  local out = {}
  for _, e in ipairs(c.elements) do
    if e.type == "text" then out[#out + 1] = e.text.text end
  end
  return out[1], out[2]
end

-- release is the banner moorings shows when a pinned window is moved by hand.
local release = {
  title = "Slack released",
  text = "Click its green button to put it back,\nor press Control-Option-Delete (⌃⌥⌫).",
}

local tests = {}

-- Test 0: Wrapping keeps newlines, breaks at spaces within 46 characters, and leaves a
-- longer word whole.
tests[#tests + 1] = function()
  install(nil)
  local lines = B.wrap(release.text)
  check("t0 newline kept", #lines == 2 and lines[1] == "Click its green button to put it back,"
    and lines[2] == "or press Control-Option-Delete (⌃⌥⌫).", table.concat(lines, "|"))
  local long = B.wrap("Windows will not move until Hammerspoon is allowed under "
    .. "Privacy & Security, Accessibility.")
  check("t0 wraps", #long == 3 and long[1] == "Windows will not move until Hammerspoon is"
    and long[2] == "allowed under Privacy & Security," and long[3] == "Accessibility.",
    table.concat(long, "|"))
  for _, l in ipairs(long) do
    check("t0 width " .. l, utf8.len(l) <= 46)
  end
  local word = string.rep("x", 60)
  local split = B.wrap("a " .. word .. " b")
  check("t0 long word", #split == 3 and split[2] == word, table.concat(split, "|"))
  check("t0 empty", #B.wrap("") == 1 and B.wrap("")[1] == "")
  local exact = string.rep("y", 20) .. " " .. string.rep("z", 25)
  check("t0 exact fit", #B.wrap(exact) == 1, table.concat(B.wrap(exact), "|"))
  check("t0 one over", #B.wrap(exact .. "z") == 2)
end

-- Test 1: The box sits 14 points from the right and 10 below the top of the primary screen's
-- frame, and grows 16 points per body line.
tests[#tests + 1] = function()
  install(nil)
  local f = B.frame(2)
  check("t1 frame", f.x == 5120 - 380 - 14 and f.y == 35 and f.w == 380 and f.h == 74,
    string.format("%d %d %d %d", f.x, f.y, f.w, f.h))
  check("t1 one line", B.frame(1).h == 58)
  check("t1 three lines", B.frame(3).h == 90)
end

-- Test 2: A banner draws its title, body and mark on every Space above other windows, and
-- fades out after five seconds.
tests[#tests + 1] = function()
  install(nil)
  B.show(release)
  local c = world.canvases[1]
  local title, body = texts(c)
  check("t2 title", title == "Slack released", tostring(title))
  check("t2 body", body == release.text, tostring(body))
  check("t2 height", c.f.h == 74 and c.f.y == 35)
  check("t2 shown", c.shown and c.lvl == "overlay")
  check("t2 spaces", c.behavior[1] == "canJoinAllSpaces" and c.behavior[2] == "stationary")
  check("t2 mouse", c.mouse.down == true and c.mouse.enterExit == true and c.mouse.up == false)
  local img = element(c, "image")
  check("t2 mark", img ~= nil and img.frame.w == 40 and img.frame.y == 17)
  check("t2 light colors", element(c, "rectangle").fillColor.white == 0.98
    and c.elements[3].text.attrs.color.white == 0)
  check("t2 one timer", #world.timers == 1 and world.timers[1].seconds == 5)
  check("t2 up", not c.deleted)
  world.timers[1]:fire()
  check("t2 faded", c.deleted and c.deleteFade == 0.4)
end

-- Test 3: Pointing at a banner holds it open, and leaving starts the full five seconds again.
tests[#tests + 1] = function()
  install(nil)
  B.show(release)
  local c = world.canvases[1]
  c.onMouse(c, "mouseEnter")
  check("t3 timer stopped", world.timers[1].stopped == true)
  world.timers[1]:fire()
  check("t3 held", not c.deleted)
  c.onMouse(c, "mouseExit")
  local again = world.timers[2]
  check("t3 rearmed", #world.timers == 2 and again.seconds == 5 and not again.stopped)
  check("t3 still up", not c.deleted)
  world.timers[2]:fire()
  check("t3 gone", c.deleted and c.deleteFade == 0.4)
end

-- Test 4: Clicking closes the banner and runs its click action once.
tests[#tests + 1] = function()
  install(nil)
  local clicks = 0
  B.show({
    title = "moorings needs Accessibility",
    text = "Click here.",
    click = function() clicks = clicks + 1 end,
  })
  local c = world.canvases[1]
  c.onMouse(c, "mouseDown")
  check("t4 clicked", clicks == 1 and c.deleted and c.deleteFade == 0.4)
  check("t4 timer stopped", world.timers[1].stopped == true)
  c.onMouse(c, "mouseDown")
  c.onMouse(c, "mouseExit")
  check("t4 once", clicks == 1 and c.deletes == 1 and #world.timers == 1)
  B.show(release)
  local plain = world.canvases[2]
  plain.onMouse(plain, "mouseDown")
  check("t4 no action", plain.deleted)
end

-- Test 5: A new banner replaces the one on screen at once, and nothing from the old one
-- touches the new one.
tests[#tests + 1] = function()
  install(nil)
  local first = B.show(release)
  B.show({ title = "moorings can move windows", text = "Accessibility is on." })
  local a, b = world.canvases[1], world.canvases[2]
  check("t5 old gone at once", a.deleted and a.deleteFade == nil)
  check("t5 old timer stopped", world.timers[1].stopped == true)
  world.timers[1]:fire()
  first.withdraw()
  a.onMouse(a, "mouseExit")
  check("t5 new kept", not b.deleted and a.deletes == 1 and #world.timers == 2)
  world.timers[2]:fire()
  check("t5 new fades", b.deleted)
  B.show(release)
  check("t5 after close", world.canvases[3].shown and b.deletes == 1)
end

-- Test 6: A sticky banner has no timer and stays until withdrawn.
tests[#tests + 1] = function()
  install(nil)
  local h = B.show({ title = "moorings needs Accessibility", text = "x", sticky = true })
  local c = world.canvases[1]
  check("t6 no timer", #world.timers == 0)
  c.onMouse(c, "mouseEnter")
  c.onMouse(c, "mouseExit")
  check("t6 still no timer", #world.timers == 0 and not c.deleted)
  h.withdraw()
  check("t6 withdrawn", c.deleted and c.deleteFade == 0.4)
  h.withdraw()
  check("t6 withdraw once", c.deletes == 1)
end

-- Test 7: Dark mode draws a dark box with a white mark, made by swapping the SVG's black and
-- white, and each style's mark loads once.
tests[#tests + 1] = function()
  install("Dark")
  B.show(release)
  local c = world.canvases[1]
  check("t7 dark box", element(c, "rectangle").fillColor.red == 0.16)
  check("t7 white text", c.elements[3].text.attrs.color.white == 1)
  local url = element(c, "image").image.url
  check("t7 data url", url:find("data:image/svg+xml;base64,<", 1, true) == 1)
  check("t7 white fill", url:find('fill="#fff"', 1, true) ~= nil
    and url:find('fill="#000"', 1, true) == nil)
  check("t7 dark highlight", url:find('stroke="#000" stroke-width="1.1"', 1, true) ~= nil, url)
  B.show(release)
  check("t7 cached", #world.urls == 1)
  world.style = nil
  B.show(release)
  local light = element(world.canvases[3], "image").image.url
  check("t7 light black", light:find('fill="#000"', 1, true) ~= nil
    and light:find('fill="#fff"', 1, true) == nil)
  check("t7 light highlight", light:find('stroke="#fff" stroke-width="1.1"', 1, true) ~= nil)
  check("t7 two loads", #world.urls == 2)
end

-- Test 8: A mark that does not load leaves the banner without an image.
tests[#tests + 1] = function()
  install(nil)
  B.markPath = "missing.svg"
  B.show(release)
  check("t8 no image", element(world.canvases[1], "image") == nil and world.canvases[1].shown)
  install(nil)
  B.markPath = nil
  B.show(release)
  check("t8 no path", element(world.canvases[1], "image") == nil and #world.urls == 0)
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
