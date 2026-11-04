// Выбор обязательного обновления APK из GitHub Releases.
// Сервер файл не скачивает: sha256 берётся из текста релиза.
// Старая игра (client-v0.1.*) и тестовые prerelease сюда не попадают.

export const PACKAGE = 'ru.ttsufa.fiveufa';
export const MAX_APK_BYTES = 99 * 1024 * 1024;
const TAG = /^client-v(\d+)\.(\d+)\.(\d+)$/;
const SHA = /^[0-9a-f]{64}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const TTL_MS = 10 * 60 * 1000;
const RETRY_MS = 60 * 1000;
const TIMEOUT_MS = 4000;

function githubHost(host) {
  return host === 'github.com' || host.endsWith('.github.com')
    || host === 'githubusercontent.com' || host.endsWith('.githubusercontent.com');
}

// Строки описания: package, versionCode, versionName, sha256. Остальной текст не мешает.
function parseBody(body) {
  const got = {};
  for (const line of String(body || '').split(/\r?\n/)) {
    const m = line.match(/^\s*(package|versionCode|versionName|sha256)\s*:\s*(\S+)\s*$/i);
    if (!m) continue;
    const key = m[1].toLowerCase();
    if (key in got && got[key] !== m[2]) return null;
    got[key] = m[2];
  }
  if (!got.package || !got.versioncode || !got.versionname || !got.sha256) return null;
  if (!/^[1-9]\d{0,9}$/.test(got.versioncode)) return null;
  const versionCode = Number(got.versioncode);
  if (!Number.isSafeInteger(versionCode) || versionCode > 2_000_000_000) return null;
  const sha = got.sha256.toLowerCase();
  if (!SHA.test(sha)) return null;
  return { package: got.package, versionCode, versionName: got.versionname, sha256: sha };
}

function oneApk(assets) {
  if (!Array.isArray(assets)) return null;
  const apks = assets.filter((a) => a && typeof a.name === 'string' && a.name.toLowerCase().endsWith('.apk'));
  if (apks.length !== 1) return null;
  const a = apks[0];
  if (a.state && a.state !== 'uploaded') return null;
  if (!Number.isSafeInteger(a.size) || a.size < 1 || a.size > MAX_APK_BYTES) return null;
  const url = String(a.browser_download_url || '');
  if (url.length > 2000) return null;
  let u;
  try { u = new URL(url); } catch { return null; }
  if (u.protocol !== 'https:' || u.username || u.password || !githubHost(u.hostname)) return null;
  return { size: a.size, url };
}

// Один релиз → описание обновления или null, если он не подходит.
export function parseRelease(rel) {
  if (!rel || typeof rel !== 'object') return null;
  if (rel.draft || rel.prerelease) return null;
  const tag = String(rel.tag_name || '');
  const m = TAG.exec(tag);
  if (!m) return null;
  const major = Number(m[1]);
  const minor = Number(m[2]);
  const patch = Number(m[3]);
  if (major === 0 && minor === 1) return null; // client-v0.1.* — старая игра, даже с чужим текстом
  const versionName = `${major}.${minor}.${patch}`;
  const meta = parseBody(rel.body);
  if (!meta || meta.package !== PACKAGE || meta.versionName !== versionName) return null;
  const apk = oneApk(rel.assets);
  if (!apk) return null;
  return { versionCode: meta.versionCode, versionName, package: PACKAGE, sha256: meta.sha256, size: apk.size, url: apk.url, tag };
}

// Больший versionCode. Два релиза с одним номером — не гадаем.
export function pickUpdate(releases) {
  if (!Array.isArray(releases)) return null;
  const good = [];
  for (const rel of releases) {
    const u = parseRelease(rel);
    if (u) good.push(u);
  }
  good.sort((a, b) => b.versionCode - a.versionCode);
  if (!good.length || (good.length > 1 && good[0].versionCode === good[1].versionCode)) return null;
  return good[0];
}

export function createReleaseCheck({
  repo = 'maillunex-lang/5Ufa',
  token = '',
  fetchImpl = globalThis.fetch,
  now = () => Date.now(),
  ttlMs = TTL_MS,
  timeoutMs = TIMEOUT_MS,
  log = () => {},
} = {}) {
  if (!REPO.test(repo)) throw new Error('bad_repo');
  let cache = { until: 0, update: null, has: false };
  let inflight = null;

  async function pull() {
    const url = `https://api.github.com/repos/${repo}/releases?per_page=100`;
    const headers = {
      accept: 'application/vnd.github+json',
      'user-agent': '5ufa-server',
      'x-github-api-version': '2022-11-28',
    };
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await fetchImpl(url, { headers, signal: AbortSignal.timeout(timeoutMs) });
    if (!res?.ok) throw new Error(`releases_http_${res?.status ?? 0}`);
    const data = await res.json();
    if (!Array.isArray(data)) throw new Error('releases_not_array');
    return pickUpdate(data);
  }

  async function refresh() {
    try {
      const update = await pull();
      cache = { until: now() + ttlMs, update, has: true };
      return update;
    } catch (e) {
      log(String(e?.message || e).replace(/Bearer\s+\S+/gi, 'Bearer …').slice(0, 200));
      cache = { until: now() + RETRY_MS, update: cache.has ? cache.update : null, has: true };
      return cache.update;
    }
  }

  return {
    async update() {
      if (now() < cache.until) return cache.update;
      if (!inflight) inflight = refresh().finally(() => { inflight = null; });
      return inflight;
    },
  };
}
