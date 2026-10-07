/** Seeded RNG + ColorLUT + starfield matching Josh’s Lua generators. */

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
  let spare = null;

  return {
    seed,
    uniform() {
      return rand();
    },
    range(a, b) {
      return a + (b - a) * rand();
    },
    sign() {
      return rand() < 0.5 ? -1 : 1;
    },
    /** Box–Muller, matches rng:getGaussian spirit */
    gaussian() {
      if (spare !== null) {
        const v = spare;
        spare = null;
        return v;
      }
      let u = 0;
      let v = 0;
      while (u === 0) u = rand();
      while (v === 0) v = rand();
      const mag = Math.sqrt(-2 * Math.log(u));
      spare = mag * Math.cos(2 * Math.PI * v);
      return mag * Math.sin(2 * Math.PI * v);
    },
    /** Exponential(1) — Lua getExp */
    exp() {
      let u = rand();
      while (u <= 1e-12) u = rand();
      return -Math.log(u);
    },
    /** Uniform direction on sphere */
    dir3() {
      const z = rand() * 2 - 1;
      const t = rand() * Math.PI * 2;
      const r = Math.sqrt(Math.max(0, 1 - z * z));
      return [r * Math.cos(t), z, r * Math.sin(t)];
    },
    choose(arr) {
      return arr[Math.floor(rand() * arr.length)];
    },
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

/**
 * Gen.ColorLUT — midpoint-displaced Bezier, 256 texels.
 * Nebula samples .x of each LUT, so we bake the R channel curve into R8.
 */
export function generateColorLut(rng, iterations = 5, variation = 0.3, rough = 0.6) {
  let cPoints = [
    [0, 0, 0],
    [1, 1, 1],
  ];
  let v = variation;
  for (let i = 0; i < iterations; i++) {
    const next = [];
    for (let j = 0; j < cPoints.length - 1; j++) {
      const p0 = cPoints[j];
      const p1 = cPoints[j + 1];
      const pn = [
        (p0[0] + p1[0]) * 0.5 + v * rng.gaussian(),
        (p0[1] + p1[1]) * 0.5 + v * rng.gaussian(),
        (p0[2] + p1[2]) * 0.5 + v * rng.gaussian(),
      ];
      next.push(p0, pn);
    }
    next.push(cPoints[cPoints.length - 1]);
    cPoints = next;
    v *= rough;
  }

  const out = new Uint8Array(256 * 4);
  for (let i = 0; i < 256; i++) {
    const t = i / 255;
    let interp = cPoints.map((p) => p.slice());
    while (interp.length > 1) {
      const ni = [];
      for (let j = 0; j < interp.length - 1; j++) {
        const p0 = interp[j];
        const p1 = interp[j + 1];
        ni.push([
          p0[0] + (p1[0] - p0[0]) * t,
          p0[1] + (p1[1] - p0[1]) * t,
          p0[2] + (p1[2] - p0[2]) * t,
        ]);
      }
      interp = ni;
    }
    const p = interp[0];
    out[i * 4 + 0] = Math.max(0, Math.min(255, Math.round(p[0] * 255)));
    out[i * 4 + 1] = Math.max(0, Math.min(255, Math.round(p[1] * 255)));
    out[i * 4 + 2] = Math.max(0, Math.min(255, Math.round(p[2] * 255)));
    out[i * 4 + 3] = 255;
  }
  return out;
}

/** Approximate Color.FromTemperature → linear RGB, then scale. */
function tempToRgb(kelvin) {
  const t = kelvin / 100;
  let r;
  let g;
  let b;
  if (t <= 66) {
    r = 255;
    g = 99.4708025861 * Math.log(t) - 161.1195681661;
    b = t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
  } else {
    r = 329.698727446 * t ** -0.1332047592;
    g = 288.1221695283 * t ** -0.0755148492;
    b = 255;
  }
  return [
    Math.max(0, Math.min(1, r / 255)),
    Math.max(0, Math.min(1, g / 255)),
    Math.max(0, Math.min(1, b / 255)),
  ];
}

/**
 * Gen.Starfield — clustered directions + blackbody colours.
 * Returns Float32Array of [dx,dy,dz, r,g,b] per star (6 floats).
 */
export function generateStarfield(rng, count = 1200) {
  const stars = [];
  const first = rng.dir3().map((c) => c * rng.exp());
  stars.push(first);
  let sum = first.slice();
  for (let i = 0; i < count; i++) {
    const p = rng.choose(stars);
    const d = rng.dir3();
    const s = rng.exp();
    const np = [p[0] + d[0] * s, p[1] + d[1] * s, p[2] + d[2] * s];
    stars.push(np);
    sum[0] += np[0];
    sum[1] += np[1];
    sum[2] += np[2];
  }
  const n = stars.length;
  const source = [sum[0] / n, sum[1] / n, sum[2] / n];
  const brightness = 0.015;
  const data = new Float32Array(n * 6);
  for (let i = 0; i < n; i++) {
    const dx = stars[i][0] - source[0];
    const dy = stars[i][1] - source[1];
    const dz = stars[i][2] - source[2];
    const len = Math.hypot(dx, dy, dz) || 1;
    const K = rng.uniform();
    const col = tempToRgb(1600 + (15000 - 1600) * K);
    const mag = brightness * rng.exp() ** 2.5;
    const o = i * 6;
    data[o] = dx / len;
    data[o + 1] = dy / len;
    data[o + 2] = dz / len;
    data[o + 3] = col[0] * mag;
    data[o + 4] = col[1] * mag;
    data[o + 5] = col[2] * mag;
  }
  return { count: n, data };
}

export function deriveNebulaParams(seedStr) {
  const rng = makeRng(seedStr);
  const h = rng.uniform();
  const s = rng.range(0.2, 0.8);
  const l = rng.range(0.2, 0.8);
  const color = rng.colorHsl(h, s, l);
  const roughness = 0.65 + 0.05 * rng.sign() * rng.uniform() ** 2;
  const seed = rng.range(1, 1000);
  // Prefer a star near the equatorial band (native systems often do).
  const az = rng.uniform() * Math.PI * 2;
  const el = rng.range(-0.35, 0.35);
  const starDir = [
    Math.cos(el) * Math.sin(az),
    Math.sin(el),
    Math.cos(el) * Math.cos(az),
  ];
  const lutR = generateColorLut(rng);
  const lutG = generateColorLut(rng);
  const lutB = generateColorLut(rng);
  const stars = generateStarfield(rng, 1400);
  return {
    seedStr: rng.seed,
    seed,
    roughness,
    color,
    starDir,
    lutR,
    lutG,
    lutB,
    stars,
  };
}

export function randomSeedString() {
  const hi = Math.floor(Math.random() * 9e15);
  const lo = Math.floor(Math.random() * 1e6);
  return String(hi) + String(lo).padStart(6, "0");
}
