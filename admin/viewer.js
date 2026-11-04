// 3D-просмотр модели для админки (three.js, локальная копия в vendor/). Модель берётся как GLB по адресу (blob).
// Анимации: собственные клипы модели плюс клипы из других GLB-файлов (если скелет с теми же именами костей).
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

export function createViewer(host, { height = 340 } = {}) {
  host.style.position = 'relative';
  host.style.height = height + 'px';
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  } catch (e) {
    host.textContent = 'Этот браузер не показывает 3D (WebGL недоступен).';
    return null;
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const el = renderer.domElement;
  el.style.width = '100%';
  el.style.height = '100%';
  el.style.borderRadius = '8px';
  el.style.touchAction = 'none';
  host.append(el);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x14161c);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x445066, 1.2));
  const sun = new THREE.DirectionalLight(0xffffff, 1.5);
  sun.position.set(3, 6, 4);
  scene.add(sun);
  const grid = new THREE.GridHelper(6, 12, 0x555e73, 0x2a2f3a);
  scene.add(grid);
  const camera = new THREE.PerspectiveCamera(40, 1, 0.05, 200);
  camera.position.set(0, 1.4, 4);
  const controls = new OrbitControls(camera, el);
  controls.enableDamping = true;
  controls.target.set(0, 1, 0);

  const loader = new GLTFLoader();
  const clock = new THREE.Clock();
  const clips = new Map(); // ключ -> { clip, source }
  let pivot = null, model = null, mixer = null, action = null, helper = null;
  let speed = 1, playing = true, raf = 0, disposed = false, size = 1;

  function resize() {
    const w = host.clientWidth || 600, h = host.clientHeight || height;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  const ro = new ResizeObserver(resize);
  ro.observe(host);
  resize();

  function clearModel() {
    if (action) { action.stop(); action = null; }
    if (mixer) { mixer.stopAllAction(); mixer = null; }
    if (helper) { scene.remove(helper); helper.dispose?.(); helper = null; }
    if (pivot) {
      scene.remove(pivot);
      pivot.traverse((o) => {
        if (o.geometry) o.geometry.dispose();
        const m = o.material; if (m) (Array.isArray(m) ? m : [m]).forEach((x) => { for (const k of Object.keys(x)) if (x[k]?.isTexture) x[k].dispose(); x.dispose(); });
      });
    }
    pivot = model = null;
    clips.clear();
  }

  function fit() {
    // габариты: сетка (точная и по границам) и положение костей; берём наибольшую высоту,
    // потому что у моделей из разных источников разные единицы скелета
    model.updateMatrixWorld(true);
    const boxA = new THREE.Box3().setFromObject(model, true);
    const boxB = new THREE.Box3().setFromObject(model, false);
    const box = boxA.getSize(new THREE.Vector3()).y >= boxB.getSize(new THREE.Vector3()).y ? boxA : boxB;
    const bones = new THREE.Box3();
    let nb = 0;
    model.traverse((o) => { if (o.isBone) { bones.expandByPoint(o.getWorldPosition(new THREE.Vector3())); nb++; } });
    const s = box.getSize(new THREE.Vector3());
    let height = s.y, floor = box.min.y;
    if (nb > 1) {
      const bh = (bones.max.y - bones.min.y) * 1.25; // кости не доходят до макушки и ступней
      if (bh > height) { height = bh; s.y = bh; s.x = Math.max(s.x, bh * 0.6); s.z = Math.max(s.z, bh * 0.4); }
      floor = Math.min(floor, bones.min.y - (bh - (bones.max.y - bones.min.y)) * 0.2);
    }
    size = Math.max(s.x, s.y, s.z) || 1;
    model.position.y -= floor;
    controls.target.set(0, height / 2, 0);
    camera.position.set(size * 0.9, height * 0.7 + size * 0.3, size * 1.8);
    controls.update();
    grid.scale.setScalar(Math.max(0.3, size / 2));
    return { height, width: s.x };
  }

  async function load(url) {
    clearModel();
    const g = await loader.loadAsync(url);
    pivot = new THREE.Group();
    model = g.scene;
    pivot.add(model);
    scene.add(pivot);
    mixer = new THREE.AnimationMixer(model);
    for (const c of g.animations) clips.set(c.name, { clip: c, source: '' });
    const info = fit();
    return { clips: [...clips.keys()], ...info };
  }

  async function addClips(url, label) {
    const g = await loader.loadAsync(url);
    const keys = [];
    for (const c of g.animations) { const k = `${label}::${c.name}`; clips.set(k, { clip: c, source: label }); keys.push(k); }
    return keys;
  }

  function play(key, { loop = true } = {}) {
    const e = clips.get(key);
    if (!e || !mixer) return false;
    const next = mixer.clipAction(e.clip);
    next.reset();
    next.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce, Infinity);
    next.clampWhenFinished = !loop;
    if (action && action !== next) next.crossFadeFrom(action, 0.15, false);
    next.play();
    action = next;
    playing = true;
    return true;
  }

  function stop() { if (action) { action.stop(); action = null; } }

  function animate() {
    if (disposed) return;
    raf = requestAnimationFrame(animate);
    const dt = clock.getDelta();
    if (mixer && playing) mixer.update(dt * speed);
    controls.update();
    renderer.render(scene, camera);
  }
  animate();

  return {
    load, addClips, play, stop,
    clipKeys: () => [...clips.keys()],
    clipInfo: (k) => clips.get(k)?.clip,
    setSpeed: (v) => { speed = v; },
    setPlaying: (v) => { playing = v; },
    isPlaying: () => playing,
    showSkeleton: (on) => {
      if (helper) { scene.remove(helper); helper.dispose?.(); helper = null; }
      if (on && model) { helper = new THREE.SkeletonHelper(model); scene.add(helper); }
    },
    hideParts: (names) => { if (!model) return; model.traverse((o) => { if (o.name && o.isObject3D && !o.isScene) o.visible = !(names || []).includes(o.name); }); },
    setScale: (v) => { if (pivot) pivot.scale.setScalar(v || 1); },
    setYaw: (deg) => { if (pivot) pivot.rotation.y = (deg || 0) * Math.PI / 180; },
    snapshot: () => { renderer.render(scene, camera); return el.toDataURL('image/png'); },
    hasModel: () => !!model,
    dispose: () => { disposed = true; cancelAnimationFrame(raf); ro.disconnect(); clearModel(); controls.dispose(); renderer.dispose(); el.remove(); },
  };
}
