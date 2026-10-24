(function () {
  "use strict";

  // Themes mirror mac/Sources/MooringsCore/Theme.swift: bg, surface, text, muted, accent. Harbor
  // is first and the style.css dark default, Concierge is last and the light default.
  var themes = [
    ["Harbor", "#0f1012", "#0f1012", "#ffffff", "#aaa59b", "#f3e3b8"],
    ["Dragonfire", "#0d0a08", "#1a1310", "#f4e6d8", "#b89c86", "#ff7a1a"],
    ["Wildfire", "#120805", "#24100a", "#ffe9c2", "#c99a6b", "#ffb000"],
    ["Neo", "#050a05", "#0b160b", "#b8ffb0", "#5fae5a", "#33ff33"],
    ["Rose", "#0e0c0c", "#1c1919", "#f4f1ee", "#a9a3a0", "#d6282f"],
    ["Lannister", "#1a0608", "#2b0c10", "#f3e3c0", "#c2a272", "#d4a63a"],
    ["Tyrian", "#140816", "#231027", "#f0e2f5", "#b597bf", "#b04cc8"],
    ["Dunder", "#060b1f", "#0e1736", "#e3e9ff", "#8e9cc9", "#4f78ff"],
    ["Verdigris", "#0a1614", "#12241f", "#dff3ec", "#86b3a5", "#43b39a"],
    ["Arrakis", "#0c0c0d", "#18181a", "#f5f5f2", "#a8a8a3", "#c07a44"],
    ["Baby Blue", "#0a1218", "#13212a", "#eaf6fc", "#8fa9b8", "#89cff0"],
    ["Concierge", "#ece4cf", "#f6f0dd", "#1a1a17", "#5c5748", "#7a2e12"]
  ];

  function lum(hex) {
    var v = [1, 3, 5].map(function (i) {
      var c = parseInt(hex.substr(i, 2), 16) / 255;
      return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
  }
  function contrast(a, b) {
    var x = lum(a), y = lum(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }
  // Same rule as Palette.onAccent: the background when it passes AA, else black or white.
  function onAccent(bg, accent) {
    if (contrast(bg, accent) >= 4.5) return bg;
    return contrast("#ffffff", accent) >= contrast("#000000", accent) ? "#ffffff" : "#000000";
  }

  var root = document.documentElement;
  function apply(t) {
    var s = root.style;
    s.setProperty("--bg", t[1]);
    s.setProperty("--surface", t[2]);
    s.setProperty("--text", t[3]);
    s.setProperty("--muted", t[4]);
    s.setProperty("--accent", t[5]);
    s.setProperty("--on", onAccent(t[1], t[5]));
    s.colorScheme = lum(t[1]) > 0.4 ? "light" : "dark";
    try { localStorage.setItem("theme", t[0]); } catch (e) {}
  }

  var tiles = document.getElementById("tiles");
  var buttons = [];
  themes.forEach(function (t) {
    var b = document.createElement("button");
    b.type = "button";
    b.className = "tile";
    b.setAttribute("aria-pressed", "false");
    b.style.background = t[1];
    b.style.color = t[3];
    b.innerHTML = '<span class="aa" style="color:' + t[5] + '">Aa</span><span>' + t[0] + '</span>';
    b.addEventListener("click", function () {
      apply(t);
      buttons.forEach(function (x) { x.setAttribute("aria-pressed", x === b ? "true" : "false"); });
    });
    tiles.appendChild(b);
    buttons.push(b);
  });
  var saved = null;
  try { saved = localStorage.getItem("theme"); } catch (e) {}
  var pick = window.matchMedia("(prefers-color-scheme: light)").matches ? themes.length - 1 : 0;
  themes.forEach(function (t, i) { if (t[0] === saved) pick = i; });
  if (saved) apply(themes[pick]);
  buttons[pick].setAttribute("aria-pressed", "true");

  // Scenes. A rect is [left, top, width, height] in percent of the desktop under the menu bar.
  // Each step is a list of beats, and a beat changes only what it names.
  var third = 100 / 3;
  var normal = [
    { go: "keys", label: "⌃⌥←", text: "Shortcuts cycle halves and thirds", beats: [
      { win: { safari: [22, 10, 50, 72], textedit: [44, 24, 40, 62] }, z: ["textedit", "safari"], hot: "safari" },
      { win: { safari: [0, 0, 50, 100] }, key: ["⌃⌥←", "Left half"] },
      { win: { safari: [0, 0, 2 * third, 100] }, key: ["⌃⌥←", "Two thirds"] },
      { win: { safari: [0, 0, third, 100] }, key: ["⌃⌥←", "One third"] },
      { win: { safari: [0, 0, 50, 100] }, key: ["⌃⌥←", "Left half"] }
    ] },
    { go: "drag", label: "Drag", text: "Drag to an edge and see where it lands", beats: [
      { win: { safari: [0, 0, 50, 100], textedit: [44, 24, 40, 62] }, z: ["safari", "textedit"], hot: "textedit", cur: [62, 26] },
      { win: { textedit: [52, 18, 40, 62] }, cur: [70, 20] },
      { win: { textedit: [58, 12, 40, 62] }, cur: [97, 40], fp: [50, 0, 50, 100] },
      { win: { textedit: [50, 0, 50, 100] }, fp: null, cur: null }
    ] },
    { go: "organize", label: "Organize", text: "Tile or cascade from the menu", beats: [
      { win: { safari: [0, 0, 50, 100], textedit: [50, 0, 50, 100], mail: [24, 20, 48, 60] }, z: ["safari", "textedit", "mail"], hot: "mail" },
      { win: { safari: [0, 0, third, 100], textedit: [third, 0, third, 100], mail: [2 * third, 0, third, 100] }, key: ["", "Tile columns"] },
      { win: { safari: [4, 4, 58, 76], textedit: [10, 11, 58, 76], mail: [16, 18, 58, 76] }, key: ["", "Cascade all"] }
    ] },
    { go: "workspaces", label: "Workspaces", text: "Save a layout and recall it by name", beats: [
      { win: { safari: [4, 4, 58, 76], textedit: [10, 11, 58, 76], mail: [16, 18, 58, 76] }, z: ["safari", "mail", "textedit"], hot: "textedit" },
      { win: { textedit: [0, 0, 2 * third, 100], safari: [2 * third, 0, third, 50], mail: [2 * third, 50, third, 50] }, key: ["", "Workspace: Writing"] }
    ] }
  ];
  var wide = [
    { go: "anchor", label: "Anchor", text: "Anchor an app to each edge", beats: [
      { win: { slack: [8, 12, 30, 70], iterm: [60, 16, 30, 66] }, z: ["iterm", "slack"], hot: "slack" },
      { win: { slack: [0, 0, 24, 100] }, strips: true, key: ["", "Anchor Slack, left"] },
      { win: { iterm: [76, 0, 24, 100] }, z: ["slack", "iterm"], hot: "iterm", key: ["", "Anchor iTerm, right"] }
    ] },
    { go: "channel", label: "Channel", text: "Everything else lands in the channel", beats: [
      { win: { slack: [0, 0, 24, 100], iterm: [76, 0, 24, 100], safari: [12, 12, 36, 72] }, z: ["slack", "iterm", "safari"], hot: "safari", strips: true },
      { win: { safari: [24, 12, 36, 72] }, key: ["", "Pushed back into the channel"] },
      { win: { safari: [24, 0, 52, 100] }, zoom: "safari", key: ["", "Green button fills the channel"] }
    ] },
    { go: "lift", label: "Green button", text: "Lift an anchored app over the channel", beats: [
      { win: { slack: [0, 0, 24, 100], iterm: [76, 0, 24, 100], safari: [24, 0, 52, 100] }, z: ["iterm", "safari", "slack"], hot: "slack", strips: true },
      { win: { slack: [0, 0, 76, 100] }, zoom: "slack", key: ["", "Lift Slack"] },
      { win: { slack: [0, 0, 24, 100] }, zoom: "slack", key: ["", "Lower Slack"] }
    ] },
    { go: "release", label: "Drag away", text: "Drag one away to let it go", beats: [
      { win: { slack: [0, 0, 24, 100], iterm: [76, 0, 24, 100], safari: [24, 0, 52, 100] }, z: ["iterm", "safari", "slack"], hot: "slack", strips: true, cur: [10, 2] },
      { win: { slack: [18, 14, 26, 70] }, cur: [28, 16] },
      { ban: true }
    ] }
  ];
  var scenes = { laptop: normal, monitor: normal, ultrawide: wide };

  var screen = document.getElementById("screen");
  var wins = {};
  Array.prototype.forEach.call(screen.querySelectorAll(".win"), function (w) { wins[w.dataset.app] = w; });
  var fp = document.getElementById("fp");
  var cursor = document.getElementById("cursor");
  var banner = document.getElementById("banner");
  var key = document.getElementById("key");
  var channel = document.getElementById("channel");
  var rail = document.getElementById("rail");
  var displayButtons = document.getElementById("displays").querySelectorAll("button");
  var still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var steps = normal, step = 0, beat = 0, state = null, timer = null, held = false;

  function place(el, r) {
    var g = 0.3;
    el.style.left = (r[0] + g) + "%";
    el.style.top = (r[1] + g) + "%";
    el.style.width = (r[2] - 2 * g) + "%";
    el.style.height = (r[3] - 2 * g) + "%";
  }
  function render() {
    Object.keys(wins).forEach(function (n) {
      var w = wins[n], r = state.win[n];
      w.classList.toggle("on", !!r);
      if (r) place(w, r);
      w.style.zIndex = String(state.z.indexOf(n) + 1);
      w.classList.toggle("hot", state.hot === n);
      w.classList.toggle("zoom", state.zoom === n);
    });
    fp.classList.toggle("on", !!state.fp);
    if (state.fp) place(fp, state.fp);
    cursor.classList.toggle("on", !!state.cur);
    if (state.cur) { cursor.style.left = state.cur[0] + "%"; cursor.style.top = state.cur[1] + "%"; }
    banner.classList.toggle("on", !!state.ban);
    channel.classList.toggle("on", !!state.strips);
    key.classList.toggle("on", !!state.key);
    if (state.key) key.innerHTML = (state.key[0] ? "<kbd>" + state.key[0] + "</kbd>" : "") + state.key[1];
  }
  function apply(b, first) {
    if (first) state = { win: {}, z: [], hot: null, zoom: null, fp: null, cur: null, ban: false, strips: false, key: null };
    else { state.zoom = null; state.key = null; }
    Object.keys(b).forEach(function (k) {
      if (k === "win") Object.keys(b.win).forEach(function (n) { state.win[n] = b.win[n]; });
      else state[k] = b[k];
    });
    render();
  }
  function schedule() {
    clearTimeout(timer);
    if (still) return;
    var last = beat === steps[step].beats.length - 1;
    timer = setTimeout(function () {
      if (!last) { beat++; apply(steps[step].beats[beat], false); schedule(); return; }
      held = false;
      show((step + 1) % steps.length);
    }, last ? (held ? 6000 : 2200) : 1150);
  }
  function show(i) {
    step = i; beat = 0;
    Array.prototype.forEach.call(rail.children, function (b, j) { b.setAttribute("aria-current", j === i ? "true" : "false"); });
    apply(steps[i].beats[0], true);
    if (still) {
      steps[i].beats.slice(1).forEach(function (b) { apply(b, false); });
      return;
    }
    schedule();
  }
  function buildRail() {
    rail.innerHTML = "";
    steps.forEach(function (s, i) {
      var b = document.createElement("button");
      b.type = "button";
      b.innerHTML = "<b>" + s.label + "</b>" + s.text;
      b.addEventListener("click", function () {
        held = true;
        show(i);
      });
      rail.appendChild(b);
    });
  }
  function setDisplay(d) {
    steps = scenes[d];
    screen.dataset.display = d;
    Array.prototype.forEach.call(displayButtons, function (b) { b.setAttribute("aria-pressed", b.dataset.display === d ? "true" : "false"); });
    buildRail();
    show(0);
  }
  Array.prototype.forEach.call(displayButtons, function (b) {
    b.addEventListener("click", function () { held = false; setDisplay(b.dataset.display); });
  });
  setDisplay(scenes[location.hash.slice(1)] ? location.hash.slice(1) : "monitor");

  // Copy buttons.
  Array.prototype.forEach.call(document.querySelectorAll("[data-copy]"), function (b) {
    b.addEventListener("click", function () {
      var done = function () { b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1400); };
      if (navigator.clipboard) navigator.clipboard.writeText(b.dataset.copy).then(done);
    });
  });

  // Show the newest version. The download links use the fixed-name asset on the latest release.
  fetch("https://api.github.com/repos/dcadolph/moorings/releases/latest")
    .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
    .then(function (rel) {
      var ver = document.getElementById("ver");
      ver.textContent = rel.tag_name + ". " + ver.textContent;
    })
    .catch(function () {});
})();
