/* KuroCat homepage behaviour.
   Works without GSAP (content is visible by default); GSAP only adds the entrance,
   the size bars and list staggers. The scroll story and 3D keyboard use plain rAF. */
(function () {
  'use strict';

  var T = window.KURO_I18N || {};
  var BASE = typeof window.KUROCAT_ASSET_BASE === 'string' ? window.KUROCAT_ASSET_BASE : '';
  var BUILD = window.KUROCAT_BUILD || 'dev';
  var root = document.documentElement;
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var isMobileLayout = function () { return window.matchMedia('(max-width: 900px)').matches; };
  var $ = function (sel, el) { return (el || document).querySelector(sel); };
  var $$ = function (sel, el) { return Array.prototype.slice.call((el || document).querySelectorAll(sel)); };
  var pet = function () { return window.KuroWebPet || null; };

  function store(key, value) {
    try {
      if (value === undefined) return JSON.parse(localStorage.getItem(key));
      localStorage.setItem(key, JSON.stringify(value));
    } catch (e) { return null; }
    return null;
  }

  /* ---------- Toast ---------- */
  var toastEl = $('#toast');
  var toastTimer = 0;
  function toast(msg) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.classList.remove('show'); }, 1900);
  }

  /* ---------- Nav ---------- */
  var nav = $('#nav');
  var menuBtn = $('#navMenu');
  var drawer = $('#navDrawer');
  function setMenu(open) {
    if (!menuBtn || !drawer) return;
    menuBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
    drawer.classList.toggle('open', open);
  }
  if (menuBtn) menuBtn.addEventListener('click', function () { setMenu(menuBtn.getAttribute('aria-expanded') !== 'true'); });
  if (drawer) drawer.addEventListener('click', function (e) { if (e.target.closest('a')) setMenu(false); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') setMenu(false); });

  var navLinks = $$('.nav-links a[data-nav]');
  var navTargets = navLinks.map(function (a) { return document.getElementById(a.getAttribute('data-nav')); });

  /* ---------- OS detection & download ---------- */
  function detectOS() {
    var p = ((navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '').toLowerCase();
    var ua = navigator.userAgent.toLowerCase();
    if (/iphone|ipad|ipod|android/.test(ua)) return null;
    if (p.indexOf('mac') > -1 || /mac os x/.test(ua)) return 'mac';
    if (p.indexOf('win') > -1 || /windows/.test(ua)) return 'win';
    if (p.indexOf('linux') > -1 || /linux|x11|cros/.test(ua)) return 'linux';
    return null;
  }
  var os = detectOS();
  if (os) {
    var col = $('.dl-col[data-os="' + os + '"]');
    if (col) {
      col.classList.add('is-detected');
      col.setAttribute('data-yours', T.your_os || '');
    }
    var label = $('#heroDlLabel');
    var osName = T['os_' + os];
    if (label && osName && T.dl_for) label.textContent = T.dl_for.replace('{os}', osName);
  }
  root.classList.toggle('is-mac', os === 'mac');

  $$('.arch').forEach(function (group) {
    var colEl = group.closest('.dl-col');
    group.addEventListener('click', function (e) {
      var btn = e.target.closest('button[data-arch]');
      if (!btn) return;
      var arch = btn.getAttribute('data-arch');
      $$('button[data-arch]', group).forEach(function (b) { b.setAttribute('aria-selected', b === btn ? 'true' : 'false'); });
      $$('[data-arch-panel]', colEl).forEach(function (p) { p.hidden = p.getAttribute('data-arch-panel') !== arch; });
    });
  });
  if (/aarch64|arm64|armv8/i.test(navigator.userAgent)) {
    var armBtn = $('button[data-arch="arm"]');
    if (armBtn) armBtn.click();
  }

  /* ---------- Copy ---------- */
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    return new Promise(function (resolve, reject) {
      var ta = document.createElement('textarea');
      ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
      document.body.removeChild(ta);
      if (ok) resolve(); else reject(new Error('copy failed'));
    });
  }
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.copy[data-copy]');
    if (!btn) return;
    copyText(btn.getAttribute('data-copy')).then(function () {
      btn.classList.add('done');
      setTimeout(function () { btn.classList.remove('done'); }, 1600);
      toast(T.copied || 'Copied');
    }, function () { toast(T.copy_fail || 'Copy failed'); });
  });

  /* ---------- Reward dialog ---------- */
  var dlg = $('#rewardDialog');
  var openReward = $('#openRewardBtn');
  if (dlg && openReward && typeof dlg.showModal === 'function') {
    openReward.addEventListener('click', function () { dlg.showModal(); });
    $('#closeRewardBtn').addEventListener('click', function () { dlg.close(); });
    dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
  } else if (openReward) {
    openReward.addEventListener('click', function () {
      window.open(BASE + 'assets/kurocat_reward.jpg', '_blank', 'noopener');
    });
  }

  /* ---------- GitHub stars ---------- */
  function fmtCount(n) {
    if (typeof n !== 'number') return null;
    return n >= 1000 ? (n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, '') + 'k' : String(n);
  }
  function paintRepo(data) {
    if (!data) return;
    var s = fmtCount(data.stars), f = fmtCount(data.forks);
    if (s) $$('[data-gh-stars]').forEach(function (el) { el.textContent = s; });
    if (f) $$('[data-gh-forks]').forEach(function (el) { el.textContent = f; });
  }
  var cached = store('kuro-gh');
  if (cached && cached.t && Date.now() - cached.t < 36e5) {
    paintRepo(cached);
  } else {
    if (cached) paintRepo(cached);
    if (window.fetch) {
      fetch('https://api.github.com/repos/chanke17/KuroCat', { headers: { Accept: 'application/vnd.github+json' } })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (j) {
          if (!j || typeof j.stargazers_count !== 'number') return;
          var data = { stars: j.stargazers_count, forks: j.forks_count, t: Date.now() };
          store('kuro-gh', data);
          paintRepo(data);
        })
        .catch(function () { /* keep static labels */ });
    }
  }

  /* ---------- Stage: editor typing, try button, float label ---------- */
  var stage = $('#stage');
  var typedEl = $('#typedText');
  var typedLine = typedEl ? typedEl.parentNode : null;
  var captionEl = $('#stageCaption');
  var typed = '';
  var lastTypedAt = 0;
  var stageMode = 'desk';

  function renderTyped() {
    if (!typedEl) return;
    typedEl.textContent = typed;
    if (typedLine) typedLine.classList.toggle('has-text', typed.length > 0);
  }
  function pushChar(ch) {
    typed += ch;
    if (typed.length > 48) typed = typed.slice(typed.length - 48);
    lastTypedAt = performance.now();
    renderTyped();
  }

  function stageInView() {
    if (!stage) return false;
    var r = stage.getBoundingClientRect();
    return r.bottom > 80 && r.top < window.innerHeight - 80;
  }

  window.addEventListener('keydown', function (e) {
    if (stageMode !== 'desk' || !stageInView()) return;
    var t = e.target;
    var tag = t && t.tagName ? t.tagName.toLowerCase() : '';
    if (tag === 'input' || tag === 'textarea' || tag === 'select' || (t && t.isContentEditable)) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'Backspace') { typed = typed.slice(0, -1); renderTyped(); return; }
    if (e.key === ' ') {
      var typingNow = performance.now() - lastTypedAt < 2500;
      var onPage = !document.activeElement || document.activeElement === document.body;
      if (typingNow && onPage) e.preventDefault();
      if (typingNow || onPage) pushChar(' ');
      return;
    }
    if (e.key && e.key.length === 1) pushChar(e.key);
  });

  var tryBtn = $('#tryBtn');
  var tryTimer = 0;
  if (tryBtn) {
    tryBtn.addEventListener('click', function () {
      var p = pet();
      var text = T.typed_try || 'meow';
      var i = 0;
      typed = '';
      renderTyped();
      if (p) p.setPose('typing');
      clearInterval(tryTimer);
      tryTimer = setInterval(function () {
        if (i < text.length) { pushChar(text.charAt(i)); i += 1; return; }
        clearInterval(tryTimer);
        setTimeout(function () { var q = pet(); if (q && q.getPose() === 'typing' && stageMode === 'desk') q.setPose('idle'); }, 900);
      }, 170);
    });
  }

  window.addEventListener('kuro:keys', function (e) {
    var el = $('#petKeyCounter');
    if (el && e.detail) el.textContent = 'KEYS ' + e.detail.total;
  });

  var floatBtn = $('#petFloatToggle');
  function syncFloatLabel() {
    var p = pet();
    var lbl = $('#petFloatLabel');
    if (!p || !lbl) return;
    var on = p.isUndocked();
    lbl.textContent = on ? (T.float_off || 'Back') : (T.float_on || 'Float');
    if (floatBtn) floatBtn.classList.toggle('active', on);
  }
  ['#petFloatToggle', '#petDockBackBtn', '#floatDockBtn'].forEach(function (sel) {
    var b = $(sel);
    if (b) b.addEventListener('click', function () { setTimeout(syncFloatLabel, 0); });
  });

  /* ---------- Scroll story: steps drive the live cat ---------- */
  var steps = $$('.step');
  var activeStep = null;
  var stepTimers = [];
  var CAPTIONS = { type: T.cap_type, hunt: T.cap_hunt, pet: T.cap_pet, sleep: T.cap_sleep, obs: T.cap_obs };

  function clearStepTimers() {
    stepTimers.forEach(function (id) {
      if (id && typeof id.cleanup === 'function') { id.cleanup(); return; }
      clearTimeout(id); clearInterval(id);
    });
    stepTimers = [];
    var p = pet();
    if (p) p.releaseKeys();
  }
  function later(fn, ms) { stepTimers.push(setTimeout(fn, ms)); }
  function every(fn, ms) { stepTimers.push(setInterval(fn, ms)); }

  function runStep(name) {
    var p = pet();
    if (!p) return;
    if (name === 'type') {
      var cycle = function () {
        p.setPose('typing');
        later(function () { p.setPose('idle'); p.holdKeys(['KeyA', 'KeyS', 'KeyD']); }, 1800);
        later(function () { p.holdKeys(['KeyA', 'KeyS', 'KeyD', 'KeyF']); }, 3300);
        later(function () { p.releaseKeys(); }, 5000);
      };
      cycle();
      every(cycle, 5600);
    } else if (name === 'hunt') {
      // A synthetic darting "cursor": the head and eyes chase it while hunting energy stays high,
      // so the crouch, round pupils and quick tail are all visible without a real mouse.
      p.setPose('idle');
      var t0 = performance.now();
      var userMoved = 0;
      var onMove = function () { userMoved = performance.now(); };
      window.addEventListener('pointermove', onMove, { passive: true });
      stepTimers.push({ cleanup: function () { window.removeEventListener('pointermove', onMove); } });
      every(function () {
        var t = (performance.now() - t0) / 1000;
        var phase = t % 4.4;
        if (phase < 3) p.hunt(1);
        if (performance.now() - userMoved > 1500) {
          p.look(Math.sin(t * 5.1) * 0.85, Math.sin(t * 3.3 + 1) * 0.45 + 0.15);
        }
      }, 60);
    } else if (name === 'pet') {
      var petCycle = function () {
        p.setPose('petHead');
        later(function () { p.setPose('drag'); }, 2800);
      };
      petCycle();
      every(petCycle, 5800);
    } else if (name === 'sleep') {
      p.setPose('sleep');
    } else if (name === 'obs') {
      p.setPose('typing');
    } else {
      p.setPose('idle');
    }
  }

  function setStep(name) {
    if (name === activeStep) return;
    activeStep = name;
    clearStepTimers();
    steps.forEach(function (s) { s.classList.toggle('is-active', s.getAttribute('data-step') === name); });
    stageMode = name === 'obs' ? 'green' : (name ? 'focus' : 'desk');
    if (stage) stage.setAttribute('data-mode', stageMode);
    if (captionEl) captionEl.textContent = (name && CAPTIONS[name]) || T.cap_desk || captionEl.textContent;
    runStep(name);
  }

  function updateStory() {
    if (!steps.length) return;
    var line = window.innerHeight * (isMobileLayout() ? 0.7 : 0.5);
    var found = null;
    for (var i = 0; i < steps.length; i++) {
      var r = steps[i].getBoundingClientRect();
      if (r.top <= line && r.bottom >= line) { found = steps[i].getAttribute('data-step'); break; }
    }
    if (!found) {
      var last = steps[steps.length - 1].getBoundingClientRect();
      if (last.bottom < line) found = 'obs';
    }
    setStep(found);
  }

  /* ---------- Scroll loop (nav state, story, active link, keyboard tilt) ---------- */
  var kbStage = $('#kbStage');
  var kb3d = null;
  var ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      ticking = false;
      if (nav) nav.classList.toggle('is-scrolled', window.scrollY > 8);
      updateStory();
      var mid = window.innerHeight * 0.35;
      var current = null;
      navTargets.forEach(function (sec, i) {
        if (!sec) return;
        var r = sec.getBoundingClientRect();
        if (r.top <= mid && r.bottom > mid) current = navLinks[i];
      });
      navLinks.forEach(function (a) { a.classList.toggle('is-active', a === current); });
      if (kb3d && kbStage) {
        var kr = kbStage.getBoundingClientRect();
        var prog = 1 - (kr.top + kr.height) / (window.innerHeight + kr.height);
        kb3d.setProgress(Math.max(0, Math.min(1, prog)));
      }
    });
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll);
  window.addEventListener('kuro:ready', onScroll);
  onScroll();

  /* ---------- Keyboard section (flat fallback + lazy Three.js) ---------- */
  var MODS = (T.kb_mods && (os === 'mac' ? T.kb_mods.mac : T.kb_mods.other)) || ['Ctrl', 'Alt', 'Win'];
  var LAYOUT = [
    [['Escape', 'esc', 1, 1], ['Digit1', '1'], ['Digit2', '2'], ['Digit3', '3'], ['Digit4', '4'], ['Digit5', '5'], ['Digit6', '6'], ['Digit7', '7'], ['Digit8', '8'], ['Digit9', '9'], ['Digit0', '0'], ['Minus', '-'], ['Equal', '='], ['Backspace', '⌫', 2, 1]],
    [['Tab', 'tab', 1.5, 1], ['KeyQ', 'Q'], ['KeyW', 'W'], ['KeyE', 'E'], ['KeyR', 'R'], ['KeyT', 'T'], ['KeyY', 'Y'], ['KeyU', 'U'], ['KeyI', 'I'], ['KeyO', 'O'], ['KeyP', 'P'], ['BracketLeft', '['], ['BracketRight', ']'], ['Backslash', '\\', 1.5]],
    [['CapsLock', 'caps', 1.75, 1], ['KeyA', 'A'], ['KeyS', 'S'], ['KeyD', 'D'], ['KeyF', 'F'], ['KeyG', 'G'], ['KeyH', 'H'], ['KeyJ', 'J'], ['KeyK', 'K'], ['KeyL', 'L'], ['Semicolon', ';'], ['Quote', "'"], ['Enter', 'enter', 2.25, 1]],
    [['ShiftLeft', 'shift', 2.25, 1], ['KeyZ', 'Z'], ['KeyX', 'X'], ['KeyC', 'C'], ['KeyV', 'V'], ['KeyB', 'B'], ['KeyN', 'N'], ['KeyM', 'M'], ['Comma', ','], ['Period', '.'], ['Slash', '/'], ['ShiftRight', 'shift', 2.75, 1]],
    [['ControlLeft', MODS[0], 1.25, 1], ['AltLeft', MODS[1], 1.25, 1], ['MetaLeft', MODS[2], 1.25, 1], ['Space', '', 6.25, 1], ['MetaRight', MODS[2], 1.25, 1], ['AltRight', MODS[1], 1.25, 1], ['ContextMenu', 'menu', 1.25, 1], ['ControlRight', MODS[0], 1.25, 1]]
  ].map(function (row) {
    return row.map(function (k) { return { code: k[0], legend: k[1], w: k[2] || 1, mod: !!k[3] }; });
  });

  var flatKeys = {};
  var kbFlat = $('#kbFlat');
  if (kbFlat) {
    LAYOUT.forEach(function (row) {
      var rowEl = document.createElement('div');
      rowEl.className = 'kb-row';
      row.forEach(function (k) {
        var el = document.createElement('span');
        el.className = 'kb-key' + (k.mod ? ' is-mod' : '');
        el.style.gridColumn = 'span ' + Math.round(k.w * 4);
        el.textContent = k.legend;
        el.setAttribute('data-code', k.code);
        rowEl.appendChild(el);
        flatKeys[k.code] = el;
      });
      kbFlat.appendChild(rowEl);
    });
  }

  var held = new Set();
  var best = 0;
  var nowEl = $('#nkroNow');
  var bestEl = $('#nkroBest');
  function paintKey(code, down) {
    if (flatKeys[code]) flatKeys[code].classList.toggle('is-down', down);
    if (kb3d) { if (down) kb3d.press(code); else kb3d.release(code); }
  }
  function paintMeter() {
    if (nowEl) nowEl.textContent = held.size;
    if (held.size > best) { best = held.size; if (bestEl) bestEl.textContent = best; }
  }
  function kbVisible() {
    if (!kbStage) return false;
    var r = kbStage.getBoundingClientRect();
    return r.bottom > 0 && r.top < window.innerHeight;
  }
  window.addEventListener('keydown', function (e) {
    if (!kbVisible() || !e.code) return;
    if (!held.has(e.code)) { held.add(e.code); paintKey(e.code, true); paintMeter(); }
  });
  window.addEventListener('keyup', function (e) {
    if (e.key === 'Meta') { held.forEach(function (c) { paintKey(c, false); }); held.clear(); paintMeter(); return; }
    if (held.has(e.code)) { held.delete(e.code); paintKey(e.code, false); paintMeter(); }
  });
  window.addEventListener('blur', function () { held.forEach(function (c) { paintKey(c, false); }); held.clear(); paintMeter(); });

  // Touch screens have no keyboard: tapping the flat keys works too (multi-touch counts).
  if (kbFlat) {
    var touchCodes = {};
    kbFlat.addEventListener('pointerdown', function (e) {
      var keyEl = e.target.closest('.kb-key');
      if (!keyEl) return;
      var code = keyEl.getAttribute('data-code');
      touchCodes[e.pointerId] = code;
      if (!held.has(code)) { held.add(code); paintKey(code, true); paintMeter(); }
    });
    var lift = function (e) {
      var code = touchCodes[e.pointerId];
      if (!code) return;
      delete touchCodes[e.pointerId];
      held.delete(code); paintKey(code, false); paintMeter();
    };
    ['pointerup', 'pointercancel', 'pointerleave'].forEach(function (t) { kbFlat.addEventListener(t, lift); });
  }

  var demoPlayed = false;
  function playDemo() {
    if (demoPlayed || reduceMotion) return;
    demoPlayed = true;
    ['KeyK', 'KeyU', 'KeyR', 'KeyO', 'KeyC', 'KeyA', 'KeyT'].forEach(function (code, i) {
      setTimeout(function () { if (!held.has(code)) paintKey(code, true); }, 500 + i * 190);
      setTimeout(function () { if (!held.has(code)) paintKey(code, false); }, 500 + i * 190 + 260);
    });
  }

  function canUse3D() {
    if (reduceMotion || isMobileLayout()) return false;
    if (!window.matchMedia('(pointer: fine)').matches) return false;
    try {
      var c = document.createElement('canvas');
      return !!(c.getContext('webgl2') || c.getContext('webgl'));
    } catch (e) { return false; }
  }

  if (kbStage && 'IntersectionObserver' in window) {
    var started = false;
    new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        if (entry.intersectionRatio > 0.35) playDemo();
        if (started || !canUse3D()) return;
        started = true;
        import(new URL(BASE + 'keyboard3d.js?v=' + BUILD, document.baseURI).href)
          .then(function (mod) {
            kb3d = mod.createKeyboard3D({ canvas: $('#kbCanvas'), container: kbStage, layout: LAYOUT });
            kbStage.classList.add('is-3d');
            held.forEach(function (c) { kb3d.press(c); });
            onScroll();
          })
          .catch(function (err) { if (window.console) console.warn('3D keyboard unavailable, using flat keyboard.', err); });
      });
    }, { rootMargin: '300px 0px', threshold: [0, 0.35] }).observe(kbStage);
  }

  /* ---------- Skins: second renderer for the preview ---------- */
  var skinCanvas = $('#skinCanvas');
  var skinView = $('#skinView');
  var skinName = $('#skinName');
  var skinDesc = $('#skinDesc');
  var R = window.KuroRenderer, S = window.KuroSpec;
  var preview = { skins: {}, id: 'siamese', skin: null, eye: 'siameseBlue', state: null, visible: false, yaw: 0, pitch: 0, nextBlink: 2 };

  function kbThemeFor(id) {
    return id === 'black' ? 'classicMilk' : (id === 'siamese' || id === 'mackerel-tabby' ? 'retroCream' : 'classicMilk');
  }
  function setPreviewSkin(id) {
    var entry = preview.skins[id];
    preview.id = id;
    if (entry) { preview.skin = entry.skin; preview.eye = entry.eye; preview.needsFrame = true; }
    $$('.swatch').forEach(function (sw) {
      var on = sw.getAttribute('data-skin-id') === id;
      sw.classList.toggle('active', on);
      sw.setAttribute('aria-checked', on ? 'true' : 'false');
      if (on) {
        if (skinName) skinName.textContent = sw.getAttribute('data-name');
        if (skinDesc) skinDesc.textContent = sw.getAttribute('data-desc');
        if (skinView) skinView.style.setProperty('--tint', getComputedStyle(sw).getPropertyValue('--bg'));
      }
    });
    if (window.gsap && skinCanvas && !reduceMotion) {
      window.gsap.fromTo(skinCanvas, { opacity: 0.2, y: 14, scale: 0.98 }, { opacity: 1, y: 0, scale: 1, duration: 0.7, ease: 'expo.out' });
    }
  }
  $$('.swatch').forEach(function (sw) {
    sw.addEventListener('click', function () { setPreviewSkin(sw.getAttribute('data-skin-id')); });
    sw.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
      var list = $$('.swatch');
      var i = list.indexOf(sw) + (e.key === 'ArrowRight' ? 1 : -1);
      var next = list[(i + list.length) % list.length];
      next.focus(); next.click();
      e.preventDefault();
    });
  });
  window.addEventListener('kuro:skin', function (e) {
    if (e.detail && e.detail.id && e.detail.id !== preview.id) setPreviewSkin(e.detail.id);
  });

  if (skinCanvas && R && S) {
    var sctx = skinCanvas.getContext('2d');
    preview.state = R.createDefaultState();
    fetch(BASE + 'pet/skins.json?v=' + BUILD)
      .then(function (r) { return r.json(); })
      .then(function (list) {
        list.forEach(function (entry) {
          var resolved = S.resolveSkin(entry.skin);
          if (R.preloadDecorations) R.preloadDecorations(resolved.decorations);
          preview.skins[entry.id] = { skin: resolved, eye: entry.eyeTheme || 'siameseBlue' };
        });
        setPreviewSkin(preview.id);
      })
      .catch(function () { /* the main pet still works */ });

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (en) { preview.visible = en.isIntersecting; });
      }, { rootMargin: '100px' }).observe(skinCanvas);
    }
    window.addEventListener('pointermove', function (e) {
      if (!preview.visible) return;
      var r = skinCanvas.getBoundingClientRect();
      preview.yaw = Math.max(-1, Math.min(1, (e.clientX - (r.left + r.width / 2)) / Math.max(240, window.innerWidth * 0.4)));
      preview.pitch = Math.max(-1, Math.min(1, (e.clientY - (r.top + r.height * 0.42)) / Math.max(200, window.innerHeight * 0.45))) * 0.8;
    }, { passive: true });

    var last = performance.now();
    var drawPreview = function (now) {
      var dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      var st = preview.state;
      if ((preview.visible || preview.needsFrame) && preview.skin && st) {
        preview.needsFrame = false;
        st.time += dt;
        st.tailPhase += dt * 2.2;
        if (st.time >= preview.nextBlink) {
          var el = st.time - preview.nextBlink;
          if (el < 0.08) st.blinkProgress = el / 0.08;
          else if (el < 0.17) st.blinkProgress = 1 - (el - 0.08) / 0.09;
          else { st.blinkProgress = 0; preview.nextBlink = st.time + 2.4 + Math.random() * 2.6; }
        }
        var k = Math.min(1, dt * 7);
        st.headYaw += (preview.yaw - st.headYaw) * k;
        st.headPitch += (preview.pitch - st.headPitch) * k;
        st.headTilt += (preview.yaw * 0.06 - st.headTilt) * k;
        st.eyeGazeX += (preview.yaw - st.eyeGazeX) * k;
        st.eyeGazeY += (preview.pitch - st.eyeGazeY) * k;
        if (R.stepPhysicsExtras) R.stepPhysicsExtras(st, preview.skin, 'idle', dt);
        sctx.setTransform(1, 0, 0, 1, 0, 0);
        R.drawScene(sctx, preview.skin, st, { kbTheme: kbThemeFor(preview.id), eyeTheme: preview.eye, whiteOutline: true });
      }
      requestAnimationFrame(drawPreview);
    };
    requestAnimationFrame(drawPreview);
  }

  /* ---------- GSAP: entrance, size bars, list staggers, skin parallax ---------- */
  function initMotion() {
    var gsap = window.gsap;
    var ST = window.ScrollTrigger;
    if (!gsap || !ST || reduceMotion) return;
    gsap.registerPlugin(ST);

    gsap.utils.toArray('.size-bar').forEach(function (bar, i) {
      gsap.fromTo(bar, { scaleX: 0 }, {
        scaleX: 1, duration: i === 2 ? 1.8 : 1.1, ease: i === 2 ? 'power3.inOut' : 'expo.out', delay: i * 0.12,
        scrollTrigger: { trigger: '.sizes', start: 'top 78%', once: true }
      });
    });

    [['.platforms li', '.platforms'], ['.eco li', '.eco'], ['.dl-col', '.dl-grid']].forEach(function (pair) {
      var items = $$(pair[0]);
      if (!items.length) return;
      // Slide only, never fade: content stays readable even before its trigger fires.
      gsap.fromTo(items, { y: 40 }, {
        y: 0, duration: 1.1, ease: 'expo.out', stagger: 0.08,
        scrollTrigger: { trigger: pair[1], start: 'top 82%', once: true }
      });
    });

    if (skinCanvas) {
      gsap.fromTo(skinCanvas, { yPercent: 7 }, {
        yPercent: -5, ease: 'none',
        scrollTrigger: { trigger: '#skinView', start: 'top bottom', end: 'bottom top', scrub: true }
      });
    }

    gsap.fromTo('.closing-mark', { rotate: -8, scale: 0.8 }, {
      rotate: 0, scale: 1, ease: 'none',
      scrollTrigger: { trigger: '.closing', start: 'top bottom', end: 'center center', scrub: true }
    });

    if (!isMobileLayout()) {
      gsap.to('.stage-panel', {
        scale: 0.94, opacity: 0.4, ease: 'none',
        scrollTrigger: { trigger: '.story', start: 'bottom 90%', end: 'bottom 30%', scrub: true }
      });
    }
  }

  // GSAP loads after this file (deferred, from a CDN). Nothing waits on it: without it the
  // page is complete and static; with it the bars, staggers and parallax switch on.
  function whenGsap(tries) {
    if (window.gsap && window.ScrollTrigger) { initMotion(); return; }
    if (tries > 120) return;
    setTimeout(function () { whenGsap(tries + 1); }, 100);
  }
  whenGsap(0);
})();
