/* RYRY — ryry.ok1xoe.dev runtime: theme, shared chrome, oscilloscope (FSK trace).
   Adapted from OK1XOE.dev (js/site.js): same theme key, so the choice is shared with ok1xoe.dev. */
(function () {
  "use strict";

  var STORE = "ok1xoe-theme";
  var root = document.documentElement;
  var body = document.body;
  var lang = body.getAttribute("data-lang") || "en";
  var base = body.getAttribute("data-root") || ".";          // path to the site root from this page
  var page = body.getAttribute("data-page") || "";

  /* ── Theme ─────────────────────────────────────────── */
  function stored() { try { return localStorage.getItem(STORE); } catch (e) { return null; } }
  function systemDark() { return window.matchMedia("(prefers-color-scheme: dark)").matches; }
  function effective() {
    var s = stored();
    if (s === "dark" || s === "light") return s;
    return systemDark() ? "dark" : "light";
  }
  function applyTheme(mode) {
    if (mode) root.setAttribute("data-theme", mode);
    document.querySelectorAll(".tsw").forEach(function (b) { b.setAttribute("data-mode", effective()); });
  }
  var s0 = stored();
  if (s0 === "dark" || s0 === "light") root.setAttribute("data-theme", s0);
  function toggleTheme() {
    var next = effective() === "dark" ? "light" : "dark";
    try { localStorage.setItem(STORE, next); } catch (e) {}
    applyTheme(next);
    signalColor = null;
  }

  /* ── Texts ─────────────────────────────────────────── */
  var T = {
    en: { features: "Features", support: "Support", manual: "Manual", privacy: "Privacy", theme: "Theme",
          other: "CS", otherLabel: "Česky", tag: "Sound-card RTTY for macOS",
          operator: "Operator", navigate: "Navigate", source: "Source",
          license: "Free · GNU LGPL v3 · based on MMTTY by JE3HHT" },
    cs: { features: "Funkce", support: "Podpora", manual: "Příručka", privacy: "Soukromí", theme: "Téma",
          other: "EN", otherLabel: "English", tag: "RTTY přes zvukovou kartu pro macOS",
          operator: "Autor", navigate: "Navigace", source: "Zdrojový kód",
          license: "Zdarma · GNU LGPL v3 · založeno na MMTTY od JE3HHT" }
  }[lang];
  // this page in the other language: /x.html ↔ /cs/x.html
  function otherLangHref() {
    var file = location.pathname.split("/").pop() || "index.html";
    return lang === "cs" ? base + "/" + file : base + "/cs/" + file;
  }
  var here = lang === "cs" ? base + "/cs/" : base + "/";
  var manualHref = base + "/manual/" + (lang === "cs" ? "cs" : "en") + "/index.html";

  function themeSwitch() {
    return '<button class="tsw" type="button" aria-label="Toggle colour theme" data-mode="' + effective() + '">' +
      '<span class="track"><span class="knob"></span></span><span class="lbl">' + T.theme + "</span></button>";
  }

  function buildHeader() {
    var host = document.getElementById("site-head");
    if (!host) return;
    var nav = [
      { id: "index", href: here + "index.html#features", label: T.features },
      { id: "support", href: here + "support.html", label: T.support },
      { id: "manual", href: manualHref, label: T.manual },
      { id: "privacy", href: here + "privacy.html", label: T.privacy }
    ].map(function (n) {
      var cur = n.id === page ? ' aria-current="page"' : "";
      return '<a' + cur + ' href="' + n.href + '">' + n.label + "</a>";
    }).join("");
    host.outerHTML =
      '<header class="site-head"><div class="shell row">' +
        '<a class="wordmark-sm" href="' + here + 'index.html"><span class="pwr" aria-hidden="true"></span>RYRY' +
          '<span class="tld">by OK1XOE.dev</span></a>' +
        '<button class="menu-btn" type="button" aria-expanded="false" aria-controls="primary-nav">Menu</button>' +
        '<nav class="nav" id="primary-nav">' + nav +
          '<a href="' + otherLangHref() + '" hreflang="' + (lang === "cs" ? "en" : "cs") + '" title="' + T.otherLabel + '">' + T.other + "</a>" +
          themeSwitch() + "</nav>" +
      "</div></header>";
  }

  function buildFooter() {
    var host = document.getElementById("site-foot");
    if (!host) return;
    host.outerHTML =
      '<footer class="backpanel"><div class="shell">' +
        '<div class="bp-top">' +
          '<div><div class="wordmark-sm"><span class="pwr" aria-hidden="true"></span>RYRY<span class="tld">.ok1xoe.dev</span></div>' +
            '<div class="silk" style="margin-top:12px">' + T.tag + "</div></div>" +
          '<div class="bp-screws"><span class="screw"></span><span class="screw"></span></div>' +
        "</div>" +
        '<div class="bp-grid">' +
          '<div><div class="silk k">' + T.operator + '</div><div class="v">OK1XOE — Tomáš Kaplan<br>' +
            '<a href="mailto:tomas.kaplan@gmail.com">tomas.kaplan@gmail.com</a><br>' +
            '<a href="https://ok1xoe.dev">← OK1XOE.dev</a></div></div>' +
          '<div><div class="silk k">' + T.navigate + '</div><div class="v">' +
            '<a href="' + here + 'index.html">RYRY</a> · <a href="' + here + 'support.html">' + T.support + "</a> · " +
            '<a href="' + manualHref + '">' + T.manual + '</a> · <a href="' + here + 'privacy.html">' + T.privacy + "</a></div></div>" +
          '<div><div class="silk k">' + T.source + '</div><div class="v" style="font-family:var(--mono);font-size:.82rem">' +
            '<a href="https://github.com/ok1xoe/mmtty4mac">github.com/ok1xoe/mmtty4mac</a></div></div>' +
        "</div>" +
        '<div class="serial"><span>RYRY · cz.ok1xoe.mmtty4mac</span><span>' + T.license + "</span></div>" +
      "</div></footer>";
  }

  function wireChrome() {
    document.querySelectorAll(".tsw").forEach(function (b) { b.addEventListener("click", toggleTheme); });
    var menu = document.querySelector(".menu-btn");
    var nav = document.getElementById("primary-nav");
    if (menu && nav) {
      menu.addEventListener("click", function () {
        var open = nav.getAttribute("data-open") === "true";
        nav.setAttribute("data-open", String(!open));
        menu.setAttribute("aria-expanded", String(!open));
      });
    }
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
      if (!stored()) { applyTheme(); signalColor = null; }
    });
  }

  /* ── Oscilloscope: an RTTY (FSK) signal – the tone alternates between mark and space ── */
  var signalColor = null;
  function readSignal() { return getComputedStyle(root).getPropertyValue("--signal").trim() || "#34E2E8"; }
  function hexToRgb(h) {
    h = h.replace("#", ""); if (h.length === 3) h = h.split("").map(function (x) { return x + x; }).join("");
    var n = parseInt(h, 16); return "rgb(" + ((n >> 16) & 255) + "," + ((n >> 8) & 255) + "," + (n & 255) + ")";
  }
  function scope() {
    var c = document.getElementById("scope");
    if (!c) return;
    var ctx = c.getContext("2d");
    var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var dpr = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
    var W, H;
    function resize() {
      var r = c.getBoundingClientRect();
      W = c.width = Math.max(1, Math.round(r.width * dpr));
      H = c.height = Math.max(1, Math.round(r.height * dpr));
    }
    resize();
    window.addEventListener("resize", resize);

    function graticule(rgb) {
      ctx.strokeStyle = rgb.replace("rgb", "rgba").replace(")", ",0.10)");
      ctx.lineWidth = 1 * dpr;
      var step = 46 * dpr;
      for (var x = (W % step) / 2; x < W; x += step) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke(); }
      for (var y = (H % step) / 2; y < H; y += step) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); }
    }
    // "RYRY…" in Baudot: R = 01010, Y = 10101 – the bits alternate, so the tone alternates too
    var bits = [0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1, 1,1,0,0,1, 0,1,1,0,1];
    function trace(t, rgb, baseY, amp, alpha, glow) {
      ctx.beginPath();
      var phase = 0, cells = 22;
      for (var px = 0; px <= W; px += 1.5 * dpr) {
        var u = px / W;
        var i = Math.floor(u * cells + t * 3) % bits.length;
        var f = bits[i] ? 0.055 : 0.032;                       // mark / space
        phase += f * 1.5 * dpr * (46 / Math.max(46, W / 40));
        var y = baseY + Math.sin(phase * 6) * amp;
        if (px === 0) ctx.moveTo(px, y); else ctx.lineTo(px, y);
      }
      ctx.strokeStyle = rgb.replace("rgb", "rgba").replace(")", "," + alpha + ")");
      ctx.lineWidth = 2 * dpr;
      ctx.shadowColor = rgb; ctx.shadowBlur = glow * dpr;
      ctx.stroke();
      ctx.shadowBlur = 0;
    }
    var t = 0, raf;
    function draw(tt) {
      if (!signalColor) signalColor = hexToRgb(readSignal());
      ctx.clearRect(0, 0, W, H);
      graticule(signalColor);
      trace(tt * 0.9 + 3, signalColor, H * 0.62, H * 0.035, 0.14, 6);   // faint back trace
      trace(tt, signalColor, H * 0.70, H * 0.06, 0.5, 14);                // main trace
    }
    function frame() { draw(t); t += 0.01; raf = requestAnimationFrame(frame); }
    if (reduce) draw(0.6); else raf = requestAnimationFrame(frame);
  }

  buildHeader();
  buildFooter();
  applyTheme();
  wireChrome();
  scope();
})();
