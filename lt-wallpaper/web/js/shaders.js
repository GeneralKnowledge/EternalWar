/** WebGL2 shaders — direction-space IFS from Josh’s gen/nebula.glsl (+ stars). */

export const VERT = `#version 300 es
precision highp float;
const vec2 verts[3] = vec2[3](
  vec2(-1.0, -1.0),
  vec2( 3.0, -1.0),
  vec2(-1.0,  3.0)
);
out vec2 vUv;
void main() {
  vec2 p = verts[gl_VertexID];
  vUv = p * 0.5 + 0.5;
  gl_Position = vec4(p, 0.0, 1.0);
}
`;

export const FRAG = `#version 300 es
precision highp float;

in vec2 vUv;
out vec4 fragColor;

uniform vec2 uResolution;
uniform float uSeed;
uniform float uRoughness;
uniform vec3 uColor;
uniform vec3 uStarDir;
uniform vec3 uLutR;
uniform vec3 uLutG;
uniform vec3 uLutB;
uniform vec2 uYawPitch;
uniform float uFov;
uniform int uSamples;
uniform int uIterations;

float hash11(float x) {
  return fract(sin(x * 127.1 + uSeed * 0.13) * 43758.5453);
}

float hash21(float x, float y) {
  float px = fract(x * 123.34 + uSeed * 0.01);
  float py = fract(y * 456.21 + uSeed * 0.01);
  float d = px * (px + 45.32) + py * (py + 45.32);
  px = fract(px + d);
  py = fract(py + d);
  return fract(px * py);
}

float noise1(float x) {
  float i = floor(x);
  float f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(hash11(i), hash11(i + 1.0), f);
}

vec4 noise4(float t) {
  return fract(sin(t) * vec4(4372.137, 8371.377, 1890.643, 7777.017));
}

float smoothNoise3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float z0 = i.z * 19.0;
  float z1 = (i.z + 1.0) * 19.0;
  float n000 = hash21(i.x, i.y + z0);
  float n100 = hash21(i.x + 1.0, i.y + z0);
  float n010 = hash21(i.x, i.y + 1.0 + z0);
  float n110 = hash21(i.x + 1.0, i.y + 1.0 + z0);
  float n001 = hash21(i.x, i.y + z1);
  float n101 = hash21(i.x + 1.0, i.y + z1);
  float n011 = hash21(i.x, i.y + 1.0 + z1);
  float n111 = hash21(i.x + 1.0, i.y + 1.0 + z1);
  float nx00 = mix(n000, n100, f.x);
  float nx10 = mix(n010, n110, f.x);
  float nx01 = mix(n001, n101, f.x);
  float nx11 = mix(n011, n111, f.x);
  return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float fSmoothNoise(vec3 p, int octaves, float lac) {
  float sum = 0.0;
  float amp = 1.0;
  float norm = 0.0;
  vec3 q = p;
  for (int o = 0; o < 8; ++o) {
    if (o >= octaves) break;
    sum += amp * smoothNoise3(q);
    norm += amp;
    amp *= 0.5;
    q *= lac;
  }
  return sum / max(norm, 1e-4);
}

/* Kaliset 4D — gen/nebula.glsl magic() */
float magic(vec3 p) {
  vec4 z = vec4(vec3(0.53) + p, 0.0);
  float a = 0.0, l = 0.0, tw = 0.0, w = 1.0;
  vec4 c = vec4(0.5, 0.55, 0.45, 0.6);
  for (int i = 0; i < 30; ++i) {
    if (i >= uIterations) break;
    float m = dot(z, z);
    z = abs(z) / max(m, 1e-8) - c;
    z += 0.02 * log(1.0e-10 + noise4(float(i) + uSeed));
    z += 0.25 * sin(z);
    a += w * exp(-2.0 * (l - m) * (l - m));
    tw += w;
    if (i > 3) w *= uRoughness;
    l = m;
    c = c.yzwx;
  }
  float t = a / max(tw, 1e-4);
  return 0.5 + 0.5 * min(cos(30.0 * t), sin(40.0 * t));
}

float bgDensity(vec3 p) {
  return 0.075 + 0.100 * fSmoothNoise(p * 4.0 + uSeed, 6, 2.0);
}

float lut1(float t, float a, float b, float c) {
  t = clamp(t, 0.0, 1.0);
  if (t < 0.5) return mix(a * 0.35, b, t * 2.0);
  return mix(b, c, (t - 0.5) * 2.0);
}

vec3 lutWave(float t) {
  vec3 wave = vec3(
    lut1(t, uLutR.x, uLutR.y, uLutR.z),
    lut1(t, uLutG.x, uLutG.y, uLutG.z),
    lut1(t, uLutB.x, uLutB.y, uLutB.z)
  );
  wave *= sqrt(max(wave, vec3(0.0)));
  return wave;
}

vec3 viewDir(vec2 uv) {
  float aspect = uResolution.x / max(uResolution.y, 1.0);
  vec2 ndc = uv * 2.0 - 1.0;
  ndc.x *= aspect;
  float tanHalf = tan(uFov * 0.5);
  vec3 forward = vec3(
    cos(uYawPitch.y) * sin(uYawPitch.x),
    sin(uYawPitch.y),
    cos(uYawPitch.y) * cos(uYawPitch.x)
  );
  vec3 worldUp = vec3(0.0, 1.0, 0.0);
  vec3 right = normalize(cross(forward, worldUp));
  vec3 up = normalize(cross(right, forward));
  return normalize(forward + ndc.x * tanHalf * right + ndc.y * tanHalf * up);
}

vec3 generate(vec3 dir) {
  vec3 c = vec3(bgDensity(dir));

  /* Soft sky plate from a short IFS sample near the camera ray. */
  float mSky = magic(dir * 0.018);
  float skyT = exp(-mSky * mSky);
  c += lutWave(skyT) * 0.04 + uColor * 0.03 * skyT;

  /* Central star. */
  float d = max(0.0, 1.0 - dot(dir, normalize(uStarDir)));
  float dd = 8.0 * exp(-sqrt(4096.0 * d)) + 4.0 * exp(-sqrt(sqrt(1024.0 * d)));
  c += dd * uColor;

  /* Absorption march — gen/nebula.glsl */
  float opacity = 1.0;
  float w = 1.0 / float(max(uSamples, 1));
  vec3 march = dir * 0.040;
  const float kExtent = 12.0;

  for (int i = 0; i < 128; ++i) {
    if (i >= uSamples) break;
    float tStep = (float(i) + 0.5) * w * kExtent;
    vec3 p = march * tStep;
    float m = magic(p);
    float t = exp(-m * m);
    vec3 wave = lutWave(t);

    const float k = 6.0;
    const float q = 1.2;
    vec3 vs = exp(-q * wave * t);
    vs -= 1.25 * exp(-pow(8.0 * abs(t - 0.90), 0.75));
    vs += 0.50 * uColor * exp(-pow(10.0 * abs(t - 0.90), 0.50));
    c *= exp(-k * w * vs);
    opacity *= exp(-k * w * ((vs.x + vs.y + vs.z) / 3.0));
  }

  return c;
}

/* Procedural pinprick stars — Starfield.lua magnitude curve, hash on sphere. */
vec3 stars(vec3 dir) {
  vec3 sum = vec3(0.0);
  // A few octahedral cells for sparse gems + denser field
  for (int layer = 0; layer < 3; ++layer) {
    float scale = exp2(float(layer) * 2.0 + 4.0);
    vec3 g = floor(dir * scale);
    for (int oz = -1; oz <= 1; ++oz)
    for (int oy = -1; oy <= 1; ++oy)
    for (int ox = -1; ox <= 1; ++ox) {
      vec3 cell = g + vec3(float(ox), float(oy), float(oz));
      float h = hash21(cell.x + 17.0 * cell.z, cell.y + 31.0 * float(layer));
      if (h > 0.992 - 0.01 * float(layer)) {
        vec3 starDir = normalize(cell + 0.5 + (vec3(hash11(h), hash11(h + 1.3), hash11(h + 2.7)) - 0.5) * 0.8);
        float ang = clamp(dot(dir, starDir), 0.0, 1.0);
        float mag = pow(h, 12.0);
        float temp = mix(1600.0, 15000.0, hash11(h + 9.1));
        // rough blackbody tint
        vec3 col = mix(vec3(1.0, 0.55, 0.25), vec3(0.75, 0.85, 1.0), clamp((temp - 3000.0) / 9000.0, 0.0, 1.0));
        float bright = 0.02 * pow(mag + 0.05, 2.5) * (1.0 + 1.5 * float(2 - layer));
        /* Soft pinprick — angular gaussian in direction space (avoids hard quads). */
        float sigma = mix(0.0018, 0.00055, float(layer) * 0.45);
        float disc = exp(-((1.0 - ang) * (1.0 - ang)) / max(sigma * sigma, 1e-10));
        sum += col * bright * disc * 28.0;
      }
    }
  }
  return sum;
}

void main() {
  vec3 dir = viewDir(vUv);
  vec3 c = generate(dir);
  c += stars(dir);

  /* LT-ish tonemap (phx filter/tonemap.glsl spirit) */
  c = 1.0 - exp(-2.3 * pow(max(c, 0.0), vec3(1.25) + c));

  /* Subtle letterbox crush */
  float vig = smoothstep(1.15, 0.35, length(vUv - 0.5));
  c *= mix(0.85, 1.0, vig);

  fragColor = vec4(c, 1.0);
}
`;
