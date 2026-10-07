/** Deterministic RNG from decimal seed strings (incl. large uint64 text). */

function xmur3(str) {
  let h = 1779033703 ^ str.length;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  return function () {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h ^= h >>> 16;
    return h >>> 0;
  };
}

function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function makeRng(seedStr) {
  const seed = String(seedStr ?? "0");
  const seedFn = xmur3(seed);
  const rand = mulberry32(seedFn());
  return {
    seed,
    next: rand,
    uniform() {
      return rand();
    },
    range(a, b) {
      return a + (b - a) * rand();
    },
    sign() {
      return rand() < 0.5 ? -1 : 1;
    },
    /** HSL → RGB, components 0–1 */
    colorHsl(h, s, l) {
      const a = s * Math.min(l, 1 - l);
      const f = (n) => {
        const k = (n + h * 12) % 12;
        return l - a * Math.max(Math.min(k - 3, 9 - k, 1), -1);
      };
      return [f(0), f(8), f(4)];
    },
  };
}

export function deriveNebulaParams(seedStr) {
  const rng = makeRng(seedStr);
  const h = rng.uniform();
  const s = rng.range(0.25, 0.85);
  const l = rng.range(0.28, 0.72);
  const color = rng.colorHsl(h, s, l);
  const roughness = 0.65 + 0.05 * rng.sign() * rng.uniform() ** 2;
  const seed = rng.range(1, 1000);
  const az = rng.uniform() * Math.PI * 2;
  const starDir = [Math.cos(az), 0, Math.sin(az)];
  const lut = () => [rng.range(0.15, 0.9), rng.range(0.2, 1.0), rng.range(0.15, 0.95)];
  return {
    seedStr: rng.seed,
    seed,
    roughness,
    color,
    starDir,
    lutR: lut(),
    lutG: lut(),
    lutB: lut(),
  };
}

export function randomSeedString() {
  // Prefer large decimal-looking seeds like LT goodSeeds
  const hi = Math.floor(Math.random() * 9e15);
  const lo = Math.floor(Math.random() * 1e6);
  return String(hi) + String(lo).padStart(6, "0");
}
