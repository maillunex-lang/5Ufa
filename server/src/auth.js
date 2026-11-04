import { randomBytes, scryptSync, timingSafeEqual, createHash } from 'node:crypto';

export const sha = (s) => createHash('sha256').update(s).digest('hex');
export const newToken = () => randomBytes(32).toString('base64url');

export function hashPassword(pw) {
  const salt = randomBytes(16);
  return `s1:${salt.toString('base64')}:${scryptSync(pw, salt, 32).toString('base64')}`;
}

export function checkPassword(pw, stored) {
  if (!stored) return false;
  const [v, s, h] = stored.split(':');
  if (v !== 's1') return false;
  const got = scryptSync(pw, Buffer.from(s, 'base64'), 32);
  const want = Buffer.from(h, 'base64');
  return got.length === want.length && timingSafeEqual(got, want);
}

// Резервный код: 20 символов без похожих. Формат тестовый; игроку показывается один раз, хранится только хеш.
export function newRecoveryCode() {
  const A = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  const raw = Array.from(randomBytes(20), (x) => A[x % A.length]).join('');
  return raw.match(/.{5}/g).join('-');
}
export const normCode = (c) => String(c || '').toUpperCase().replace(/[^A-Z0-9]/g, '');

// Ограничение попыток по ключу (IP/логин).
export function makeLimiter(max, windowMs) {
  const m = new Map();
  return (key, now = Date.now()) => {
    const a = (m.get(key) || []).filter((t) => now - t < windowMs);
    if (a.length >= max) { m.set(key, a); return false; }
    a.push(now);
    m.set(key, a);
    return true;
  };
}
