// 3D keyboard for the "every key counts" section.
// Loaded on demand by site.js (desktop, WebGL, no reduced motion). Keys press down and
// light up for every physical key held at once; scroll tilts the board into view.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const UNIT = 1;
const GAP = 0.13;
const KEY_H = 0.42;
const KEY_COLOR = new THREE.Color(0xf2f2f4);
const MOD_COLOR = new THREE.Color(0xdedee3);
const HOT_COLOR = new THREE.Color(0x0071e3);

const clamp01 = (v) => Math.max(0, Math.min(1, v));
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, v) => { const t = clamp01((v - a) / (b - a)); return t * t * (3 - 2 * t); };

function legendAtlas(layout) {
  const CELL = 128;
  const COLS = 8;
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = CELL * COLS;
  const g = canvas.getContext('2d');
  g.fillStyle = '#3a3a3f';
  g.textBaseline = 'top';
  const family = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", "PingFang SC", Arial, sans-serif';
  const cells = new Map();
  let i = 0;
  layout.forEach((row) => row.forEach((k) => {
    if (!k.legend) return;
    const cx = (i % COLS) * CELL;
    const cy = Math.floor(i / COLS) * CELL;
    const single = k.legend.length === 1;
    g.font = single ? `500 54px ${family}` : `500 28px ${family}`;
    g.fillText(k.legend, cx + 18, cy + (single ? 14 : 20));
    cells.set(k.code, { u: (i % COLS) / COLS, v: 1 - (Math.floor(i / COLS) + 1) / COLS, s: 1 / COLS });
    i += 1;
  }));
  return { canvas, cells };
}

function shadowTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(128, 128, 10, 128, 128, 128);
  grad.addColorStop(0, 'rgba(0,0,0,0.85)');
  grad.addColorStop(0.55, 'rgba(0,0,0,0.35)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 256, 256);
  return new THREE.CanvasTexture(c);
}

function poolTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(128, 128, 0, 128, 128, 128);
  grad.addColorStop(0, 'rgba(130,160,220,0.30)');
  grad.addColorStop(0.5, 'rgba(90,110,170,0.10)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 256, 256);
  return new THREE.CanvasTexture(c);
}

export function createKeyboard3D({ canvas, container, layout }) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.92;
  renderer.setClearColor(0x000000, 0);

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  pmrem.dispose();

  const key = new THREE.DirectionalLight(0xffffff, 2.3);
  key.position.set(-5, 11, 6);
  scene.add(key);
  const rim = new THREE.DirectionalLight(0x8fb8ff, 0.9);
  rim.position.set(6, 3, -8);
  scene.add(rim);

  const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 200);
  const board = new THREE.Group();
  scene.add(board);

  const rows = layout.length;
  const width = 15 * UNIT;
  const depth = rows * UNIT;

  const caseMesh = new THREE.Mesh(
    new RoundedBoxGeometry(width + 0.8, 0.5, depth + 0.8, 5, 0.24),
    new THREE.MeshStandardMaterial({ color: 0xbfc1c6, metalness: 0.92, roughness: 0.3 })
  );
  caseMesh.position.y = -0.22;
  board.add(caseMesh);

  const well = new THREE.Mesh(
    new THREE.BoxGeometry(width + 0.06, 0.04, depth + 0.06),
    new THREE.MeshStandardMaterial({ color: 0x1a1a1d, metalness: 0.4, roughness: 0.7 })
  );
  well.position.y = 0.04;
  board.add(well);

  const shadow = new THREE.Mesh(
    new THREE.PlaneGeometry(width * 1.16, depth * 1.7),
    new THREE.MeshBasicMaterial({ map: shadowTexture(), transparent: true, depthWrite: false, opacity: 1 })
  );
  shadow.rotation.x = -Math.PI / 2;
  shadow.position.y = -0.5;
  board.add(shadow);

  // a soft pool of light on the floor so the board sits on something in the black section
  const pool = new THREE.Mesh(
    new THREE.PlaneGeometry(width * 2.6, depth * 4.2),
    new THREE.MeshBasicMaterial({ map: poolTexture(), transparent: true, depthWrite: false, opacity: 1 })
  );
  pool.rotation.x = -Math.PI / 2;
  pool.position.y = -0.52;
  pool.renderOrder = -2;
  shadow.renderOrder = -1;
  board.add(pool);

  const atlas = legendAtlas(layout);
  const legendTex = new THREE.CanvasTexture(atlas.canvas);
  legendTex.colorSpace = THREE.SRGBColorSpace;
  legendTex.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  const legendMat = new THREE.MeshBasicMaterial({ map: legendTex, transparent: true, depthWrite: false });

  const geoCache = new Map();
  const keys = new Map();
  layout.forEach((row, r) => {
    let x = -width / 2;
    row.forEach((k) => {
      const w = k.w * UNIT;
      const gk = k.w.toFixed(2);
      if (!geoCache.has(gk)) geoCache.set(gk, new RoundedBoxGeometry(w - GAP, KEY_H, UNIT - GAP, 3, 0.11));
      const base = k.mod ? MOD_COLOR : KEY_COLOR;
      const mat = new THREE.MeshStandardMaterial({
        color: base.clone(), roughness: 0.42, metalness: 0.0,
        emissive: new THREE.Color(0x0a6cf0), emissiveIntensity: 0
      });
      const mesh = new THREE.Mesh(geoCache.get(gk), mat);
      const baseY = KEY_H / 2 + 0.07;
      mesh.position.set(x + w / 2, baseY, -depth / 2 + r * UNIT + UNIT / 2);

      const cell = atlas.cells.get(k.code);
      if (cell) {
        const size = 0.6;
        const pg = new THREE.PlaneGeometry(size, size);
        const uv = pg.attributes.uv;
        for (let i = 0; i < uv.count; i += 1) {
          uv.setXY(i, cell.u + uv.getX(i) * cell.s, cell.v + uv.getY(i) * cell.s);
        }
        const label = new THREE.Mesh(pg, legendMat);
        label.rotation.x = -Math.PI / 2;
        label.position.set(-(w - GAP) / 2 + size / 2 + 0.04, KEY_H / 2 + 0.003, -(UNIT - GAP) / 2 + size / 2 + 0.04);
        mesh.add(label);
      }
      board.add(mesh);
      keys.set(k.code, { mesh, mat, base, baseY, down: false, depth: 0, glow: 0 });
      x += w;
    });
  });

  // ---- sizing ----
  const fov = THREE.MathUtils.degToRad(camera.fov);
  function resize() {
    const w = container.clientWidth;
    const h = container.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    const fitW = (width + 4.2) / (2 * Math.tan(fov / 2) * camera.aspect);
    const fitH = (depth + 3.4) / (2 * Math.tan(fov / 2));
    const dist = Math.max(fitW, fitH);
    const elev = THREE.MathUtils.degToRad(52);
    camera.position.set(0, Math.sin(elev) * dist, Math.cos(elev) * dist);
    camera.lookAt(0, -0.2, 0);
    camera.updateProjectionMatrix();
  }
  const ro = new ResizeObserver(resize);
  ro.observe(container);
  resize();

  // ---- interaction ----
  const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
  container.addEventListener('pointermove', (e) => {
    const r = container.getBoundingClientRect();
    pointer.tx = ((e.clientX - r.left) / r.width) * 2 - 1;
    pointer.ty = ((e.clientY - r.top) / r.height) * 2 - 1;
  }, { passive: true });
  container.addEventListener('pointerleave', () => { pointer.tx = 0; pointer.ty = 0; });

  let progress = 0;
  let running = false;
  let visible = false;
  let raf = 0;
  let last = performance.now();

  function frame(now) {
    raf = 0;
    if (!running) return;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;

    pointer.x += (pointer.tx - pointer.x) * Math.min(1, dt * 4);
    pointer.y += (pointer.ty - pointer.y) * Math.min(1, dt * 4);
    const p = smooth(0.08, 0.6, progress);
    board.rotation.x = lerp(-0.42, 0.16, p) + pointer.y * 0.04;
    board.rotation.y = lerp(-0.32, 0, p) + pointer.x * 0.07;
    board.rotation.z = lerp(0.06, 0, p);
    board.position.y = lerp(-1.1, 0, p);

    keys.forEach((k) => {
      const t = k.down ? 1 : 0;
      k.depth += (t - k.depth) * Math.min(1, dt * 26);
      k.glow += (t - k.glow) * Math.min(1, dt * (k.down ? 26 : 4.5));
      k.mesh.position.y = k.baseY - k.depth * 0.24;
      k.mat.color.copy(k.base).lerp(HOT_COLOR, k.glow);
      k.mat.emissiveIntensity = k.glow * 0.18;
      k.mat.roughness = 0.42 + k.glow * 0.3;
    });

    renderer.render(scene, camera);
    raf = requestAnimationFrame(frame);
  }
  function setRunning(on) {
    running = on;
    if (on && !raf) { last = performance.now(); raf = requestAnimationFrame(frame); }
  }
  new IntersectionObserver((entries) => {
    entries.forEach((en) => { visible = en.isIntersecting; setRunning(visible && !document.hidden); });
  }, { rootMargin: '80px' }).observe(container);
  document.addEventListener('visibilitychange', () => setRunning(visible && !document.hidden));

  return {
    press(code) { const k = keys.get(code); if (k) k.down = true; },
    release(code) { const k = keys.get(code); if (k) k.down = false; },
    setProgress(v) { progress = clamp01(v); },
  };
}
