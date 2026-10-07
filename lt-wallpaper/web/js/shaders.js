/**
 * Faithful WebGL2 port of Josh’s gen/nebula.glsl + noise.glsl primitives
 * and filter/tonemap.glsl (expmap + bezier grading), plus a light bloom.
 */

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

/** HDR nebula (linear), no tonemap — written to float target when available. */
export const NEBULA_FRAG = `#version 300 es
precision highp float;

in vec2 vUv;
out vec4 fragColor;

uniform vec2 uResolution;
uniform float uSeed;
uniform float uRoughness;
uniform vec3 uColor;
uniform vec3 uStarDir;
uniform sampler2D uLutR;
uniform sampler2D uLutG;
uniform sampler2D uLutB;
uniform vec2 uYawPitch;
uniform float uFov;
uniform int uSamples;
uniform int uIterations;

float pow2(float x) { return x * x; }

float noise(float x) { return fract(sin(x) * 4137.31315); }
float noise(vec2 x) { return noise(x.x + noise(x.y)); }
float noise(vec3 x) { return noise(x.x + noise(x.yz)); }
float noise(vec4 x) { return noise(x.x + noise(x.yzw)); }

vec4 noise4(float t) {
  return fract(sin(t) * vec4(4372.137, 8371.377, 1890.643, 7777.017));
}

float smoothNoise(vec3 p) {
  vec3 f = floor(p), i = fract(p);
  i = i * i * (3.0 - 2.0 * i);
  return mix(
    mix(mix(noise(f + vec3(0.0, 0.0, 0.0)), noise(f + vec3(1.0, 0.0, 0.0)), i.x),
        mix(noise(f + vec3(0.0, 1.0, 0.0)), noise(f + vec3(1.0, 1.0, 0.0)), i.x), i.y),
    mix(mix(noise(f + vec3(0.0, 0.0, 1.0)), noise(f + vec3(1.0, 0.0, 1.0)), i.x),
        mix(noise(f + vec3(0.0, 1.0, 1.0)), noise(f + vec3(1.0, 1.0, 1.0)), i.x), i.y),
    i.z);
}

float fSmoothNoise(vec3 p, int octaves, float lac) {
  float a = 0.0, tw = 0.0, w = 1.0;
  for (int i = 0; i < 10; i++) {
    if (i >= octaves) break;
    a += w * smoothNoise(p);
    tw += w;
    p *= 2.0;
    w /= lac;
  }
  return a / max(tw, 1e-4);
}

float magic(vec3 p) {
  vec4 z = vec4(vec3(0.53) + p, 0.0);
  float a = 0.0, l = 0.0, tw = 0.0, w = 1.0;
  vec4 c = vec4(0.5, 0.55, 0.45, 0.6);
  for (int i = 0; i < 30; ++i) {
    if (i >= uIterations) break;
    float m = dot(z, z);
    z = abs(z) / max(m, 1e-10) - c;
    z += 0.02 * log(1.0e-10 + noise4(float(i) + uSeed));
    z += 0.25 * sin(z);
    a += w * exp(-2.0 * pow2(l - m));
    tw += w;
    if (i > 3) w *= uRoughness;
    l = m;
    c = c.yzwx;
  }
  float t = a / max(tw, 1e-4);
  return 0.5 + 0.5 * min(cos(30.0 * t), sin(40.0 * t));
}

float bgDensity(vec3 p) {
  return 0.075 + 0.100 * fSmoothNoise(p * 4.0 + uSeed, 8, 2.0);
}

float sampleLut(sampler2D lut, float t) {
  return texture(lut, vec2(clamp(t, 0.0, 1.0), 0.5)).r;
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
  if (length(right) < 1e-4) right = vec3(1.0, 0.0, 0.0);
  vec3 up = normalize(cross(right, forward));
  return normalize(forward + ndc.x * tanHalf * right + ndc.y * tanHalf * up);
}

vec3 generate(vec3 dir) {
  const float kScale = 0.040;
  vec3 c = vec3(bgDensity(dir));
  float w = 1.0 / float(max(uSamples, 1));

  float d = max(0.0, 1.0 - dot(dir, normalize(uStarDir)));
  float dd = 8.0 * exp(-sqrt(4096.0 * d)) + 4.0 * exp(-sqrt(sqrt(1024.0 * d)));
  c += dd * uColor;

  vec3 march = dir * kScale;
  for (int i = 0; i < 128; ++i) {
    if (i >= uSamples) break;
    vec3 p = march * (float(i) * w);
    float t = magic(p);
    t = exp(-t * t);
    vec3 wave = vec3(
      sampleLut(uLutR, t),
      sampleLut(uLutG, t),
      sampleLut(uLutB, t)
    );
    wave *= sqrt(max(wave, vec3(0.0)));

    const float k = 6.0;
    const float q = 1.2;
    vec3 vs = exp(-q * wave * t);
    vs -= 1.25 * exp(-pow(8.0 * abs(t - 0.90), 0.75));
    vs += 0.50 * uColor * exp(-pow(10.0 * abs(t - 0.90), 0.50));
    c *= exp(-k * w * vs);
  }
  return c;
}

void main() {
  fragColor = vec4(generate(viewDir(vUv)), 1.0);
}
`;

export const STAR_VERT = `#version 300 es
precision highp float;
layout(location = 0) in vec3 aDir;
layout(location = 1) in vec3 aColor;
uniform vec2 uYawPitch;
uniform float uFov;
uniform vec2 uResolution;
uniform float uPointScale;
out vec3 vColor;
out float vAlphaScale;

void main() {
  vec3 forward = vec3(
    cos(uYawPitch.y) * sin(uYawPitch.x),
    sin(uYawPitch.y),
    cos(uYawPitch.y) * cos(uYawPitch.x)
  );
  vec3 worldUp = vec3(0.0, 1.0, 0.0);
  vec3 right = normalize(cross(forward, worldUp));
  if (dot(right, right) < 1e-6) right = vec3(1.0, 0.0, 0.0);
  vec3 up = normalize(cross(right, forward));

  float z = dot(aDir, forward);
  vAlphaScale = smoothstep(0.02, 0.12, z);
  float x = dot(aDir, right);
  float y = dot(aDir, up);
  float tanHalf = tan(uFov * 0.5);
  float aspect = uResolution.x / max(uResolution.y, 1.0);
  if (z <= 0.02) {
    gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
    gl_PointSize = 0.0;
    vColor = vec3(0.0);
    return;
  }
  gl_Position = vec4(x / (tanHalf * aspect), y / tanHalf, 0.0, 1.0);
  float mag = length(aColor);
  gl_PointSize = clamp(uPointScale * (0.45 + 22.0 * sqrt(mag)), 1.0, 14.0);
  vColor = aColor * 14.0;
}
`;

export const STAR_FRAG = `#version 300 es
precision highp float;
in vec3 vColor;
in float vAlphaScale;
out vec4 fragColor;
float pow2(float x) { return x * x; }
void main() {
  vec2 p = gl_PointCoord * 2.0 - 1.0;
  float r = length(p);
  float a = 0.5 * exp(-9.0 * sqrt(r)) + exp(-pow2(30.0 * r));
  a *= a * vAlphaScale;
  fragColor = vec4(vColor * a, a);
}
`;

export const COMPOSITE_FRAG = `#version 300 es
precision highp float;
in vec2 vUv;
out vec4 fragColor;
uniform sampler2D uScene;
uniform sampler2D uBloom;
uniform float uBloomStrength;
uniform vec2 uResolution;

float noise(float x) { return fract(sin(x) * 4137.31315); }
float noise(vec2 x) { return noise(x.x + noise(x.y)); }
vec3 noise3(float t) {
  return fract(sin(t) * vec3(4372.137, 8371.377, 1890.643));
}
float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 beziernorm3(vec3 x, vec3 y1, vec3 y2, vec3 y3) {
  vec3 y01 = mix(vec3(0.0), y1, x);
  vec3 y12 = mix(y1, y2, x);
  vec3 y23 = mix(y2, y3, x);
  vec3 y34 = mix(y3, vec3(1.0), x);
  vec3 y012 = mix(y01, y12, x);
  vec3 y123 = mix(y12, y23, x);
  vec3 y234 = mix(y23, y34, x);
  return mix(mix(y012, y123, x), mix(y123, y234, x), x);
}

vec3 tonemap(vec3 c, vec2 uv) {
  c *= 0.72;
  c = pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));

  vec2 uvp = vec2(1.0) - 2.0 * abs(vec2(0.5) - uv);
  c *= 1.0 - 0.22 * exp(-32.0 * uvp.x);
  c *= 1.0 - 0.22 * exp(-32.0 * uvp.y);

  c = 1.0 - exp(-2.30 * pow(c, vec3(1.25) + c));

  c = beziernorm3(c,
    vec3(0.25, 0.20 + 0.1 * uv.x, 0.35 - 0.15 * uv.y),
    vec3(0.40, 0.50 - 0.20 * uv.y, 0.50),
    vec3(0.80 + 0.2 * uv.y, 0.80, 0.80 - 0.40 * sqrt(max(uv.x * uv.y, 0.0)))
  );

  /* Contrast to recover IFS ridges */
  c = clamp((c - 0.5) * 1.28 + 0.5, 0.0, 1.0);

  c -= (2.0 * noise3(noise(uv * 16.0)) - vec3(1.0)) / 256.0;
  return clamp(c, 0.0, 1.0);
}

void main() {
  vec3 scene = texture(uScene, vUv).rgb;
  vec3 bloom = texture(uBloom, vUv).rgb;
  /* Mild unsharp against a tiny neighborhood to bring IFS ridges back */
  vec2 t = 1.0 / max(uResolution, vec2(1.0));
  vec3 blur = (
    texture(uScene, vUv + vec2( t.x, 0.0)).rgb +
    texture(uScene, vUv + vec2(-t.x, 0.0)).rgb +
    texture(uScene, vUv + vec2(0.0,  t.y)).rgb +
    texture(uScene, vUv + vec2(0.0, -t.y)).rgb
  ) * 0.25;
  scene = clamp(scene + (scene - blur) * 0.55, 0.0, 64.0);
  vec3 c = scene + bloom * uBloomStrength;
  fragColor = vec4(tonemap(c, vUv), 1.0);
}
`;

export const BLUR_FRAG = `#version 300 es
precision highp float;
in vec2 vUv;
out vec4 fragColor;
uniform sampler2D uSrc;
uniform vec2 uTexel;
uniform float uThreshold;

void main() {
  vec3 c = texture(uSrc, vUv).rgb;
  /* 9-tap blur; optionally threshold for bloom extract on first use */
  vec3 acc = c * 0.25;
  acc += texture(uSrc, vUv + uTexel * vec2( 1.0,  0.0)).rgb * 0.125;
  acc += texture(uSrc, vUv + uTexel * vec2(-1.0,  0.0)).rgb * 0.125;
  acc += texture(uSrc, vUv + uTexel * vec2( 0.0,  1.0)).rgb * 0.125;
  acc += texture(uSrc, vUv + uTexel * vec2( 0.0, -1.0)).rgb * 0.125;
  acc += texture(uSrc, vUv + uTexel * vec2( 1.0,  1.0)).rgb * 0.0625;
  acc += texture(uSrc, vUv + uTexel * vec2(-1.0,  1.0)).rgb * 0.0625;
  acc += texture(uSrc, vUv + uTexel * vec2( 1.0, -1.0)).rgb * 0.0625;
  acc += texture(uSrc, vUv + uTexel * vec2(-1.0, -1.0)).rgb * 0.0625;
  float l = dot(acc, vec3(0.2126, 0.7152, 0.0722));
  float m = max(0.0, l - uThreshold);
  fragColor = vec4(acc * (m / max(l, 1e-4)), 1.0);
}
`;
