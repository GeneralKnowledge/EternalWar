import {
  VERT,
  NEBULA_FRAG,
  STAR_VERT,
  STAR_FRAG,
  COMPOSITE_FRAG,
  BLUR_FRAG,
} from "./shaders.js";
import { deriveNebulaParams, randomSeedString } from "./rng.js";

const QUALITY = {
  draft: { samples: 64, iterations: 22, scale: 0.6 },
  good: { samples: 112, iterations: 28, scale: 0.9 },
  high: { samples: 128, iterations: 30, scale: 1.0 },
};

const canvas = document.getElementById("gl");
const statusEl = document.getElementById("status");
const seedInput = document.getElementById("seed");
const qualitySel = document.getElementById("quality");
const exportSel = document.getElementById("exportSize");

const gl = canvas.getContext("webgl2", {
  alpha: false,
  antialias: false,
  preserveDrawingBuffer: true,
  powerPreference: "high-performance",
});

if (!gl) {
  statusEl.textContent = "WebGL2 required";
  throw new Error("WebGL2 not available");
}

const extColor = gl.getExtension("EXT_color_buffer_float");
const extFloatLin = gl.getExtension("OES_texture_float_linear");
const useFloat = !!(extColor && extFloatLin);

function compile(type, src) {
  const sh = gl.createShader(type);
  gl.shaderSource(sh, src);
  gl.compileShader(sh);
  if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(sh);
    gl.deleteShader(sh);
    throw new Error(log || "shader compile failed");
  }
  return sh;
}

function link(vsSrc, fsSrc) {
  const prog = gl.createProgram();
  const vs = compile(gl.VERTEX_SHADER, vsSrc);
  const fs = compile(gl.FRAGMENT_SHADER, fsSrc);
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.linkProgram(prog);
  gl.deleteShader(vs);
  gl.deleteShader(fs);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    const log = gl.getProgramInfoLog(prog);
    gl.deleteProgram(prog);
    throw new Error(log || "program link failed");
  }
  return prog;
}

const nebulaProg = link(VERT, NEBULA_FRAG);
const starProg = link(STAR_VERT, STAR_FRAG);
const blurProg = link(VERT, BLUR_FRAG);
const compositeProg = link(VERT, COMPOSITE_FRAG);

function locs(prog, names) {
  const o = {};
  for (const n of names) o[n] = gl.getUniformLocation(prog, n);
  return o;
}

const nu = locs(nebulaProg, [
  "uResolution", "uSeed", "uRoughness", "uColor", "uStarDir",
  "uLutR", "uLutG", "uLutB", "uYawPitch", "uFov", "uSamples", "uIterations",
]);
const su = locs(starProg, ["uYawPitch", "uFov", "uResolution", "uPointScale"]);
const bu = locs(blurProg, ["uSrc", "uTexel", "uThreshold"]);
const cu = locs(compositeProg, ["uScene", "uBloom", "uBloomStrength", "uResolution"]);

const quadVao = gl.createVertexArray();

function makeLutTex(bytes) {
  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 256, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, bytes);
  return tex;
}

const lutTex = {
  r: makeLutTex(new Uint8Array(256 * 4)),
  g: makeLutTex(new Uint8Array(256 * 4)),
  b: makeLutTex(new Uint8Array(256 * 4)),
};

const starVao = gl.createVertexArray();
const starBuf = gl.createBuffer();
let starCount = 0;

function uploadStars(stars) {
  starCount = stars.count;
  gl.bindVertexArray(starVao);
  gl.bindBuffer(gl.ARRAY_BUFFER, starBuf);
  gl.bufferData(gl.ARRAY_BUFFER, stars.data, gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 24, 0);
  gl.enableVertexAttribArray(1);
  gl.vertexAttribPointer(1, 3, gl.FLOAT, false, 24, 12);
  gl.bindVertexArray(null);
}

function makeTarget(w, h, floating) {
  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  if (floating && useFloat) {
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, w, h, 0, gl.RGBA, gl.HALF_FLOAT, null);
  } else {
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
  }
  const fbo = gl.createFramebuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
  const ok = gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE;
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  if (!ok) throw new Error("framebuffer incomplete");
  return { tex, fbo, w, h };
}

let sceneTarget = null;
let bloomA = null;
let bloomB = null;

function ensureTargets(w, h) {
  if (sceneTarget && sceneTarget.w === w && sceneTarget.h === h) return;
  for (const t of [sceneTarget, bloomA, bloomB]) {
    if (!t) continue;
    gl.deleteTexture(t.tex);
    gl.deleteFramebuffer(t.fbo);
  }
  sceneTarget = makeTarget(w, h, true);
  const bw = Math.max(1, Math.floor(w / 2));
  const bh = Math.max(1, Math.floor(h / 2));
  bloomA = makeTarget(bw, bh, true);
  bloomB = makeTarget(bw, bh, true);
}

function lookAtNebula(starDir) {
  // Wallpaper.lua: toward -starDir, plus a slight yaw so filaments catch the frame.
  const x = -starDir[0];
  const y = -starDir[1];
  const z = -starDir[2];
  return {
    yaw: Math.atan2(x, z) + 0.35,
    pitch: Math.asin(Math.max(-0.45, Math.min(0.45, y))) + 0.08,
  };
}

const state = {
  yaw: 0,
  pitch: 0.1,
  params: null,
  dragging: false,
  lastX: 0,
  lastY: 0,
  dirty: true,
  lastMs: 0,
  rendering: false,
};

function setStatus(msg) {
  statusEl.textContent = msg;
}

function uploadLuts(p) {
  gl.bindTexture(gl.TEXTURE_2D, lutTex.r);
  gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 256, 1, gl.RGBA, gl.UNSIGNED_BYTE, p.lutR);
  gl.bindTexture(gl.TEXTURE_2D, lutTex.g);
  gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 256, 1, gl.RGBA, gl.UNSIGNED_BYTE, p.lutG);
  gl.bindTexture(gl.TEXTURE_2D, lutTex.b);
  gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 256, 1, gl.RGBA, gl.UNSIGNED_BYTE, p.lutB);
}

function applySeedFromInput() {
  state.params = deriveNebulaParams(seedInput.value.trim() || "0");
  uploadLuts(state.params);
  uploadStars(state.params.stars);
  const look = lookAtNebula(state.params.starDir);
  state.yaw = look.yaw;
  state.pitch = look.pitch;
  state.dirty = true;
  setStatus(
    `Seed ${state.params.seedStr.slice(0, 18)}… · roughness ${state.params.roughness.toFixed(3)}`,
  );
}

function resize(scale = 1) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = Math.max(1, Math.floor(canvas.clientWidth * dpr * scale));
  const h = Math.max(1, Math.floor(canvas.clientHeight * dpr * scale));
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
    state.dirty = true;
  }
}

function bindLuts() {
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, lutTex.r);
  gl.uniform1i(nu.uLutR, 0);
  gl.activeTexture(gl.TEXTURE1);
  gl.bindTexture(gl.TEXTURE_2D, lutTex.g);
  gl.uniform1i(nu.uLutG, 1);
  gl.activeTexture(gl.TEXTURE2);
  gl.bindTexture(gl.TEXTURE_2D, lutTex.b);
  gl.uniform1i(nu.uLutB, 2);
}

function drawNebula(w, h, samples, iterations) {
  const p = state.params;
  gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.fbo);
  gl.viewport(0, 0, w, h);
  gl.disable(gl.BLEND);
  gl.clearColor(0, 0, 0, 1);
  gl.clear(gl.COLOR_BUFFER_BIT);
  gl.useProgram(nebulaProg);
  gl.bindVertexArray(quadVao);
  bindLuts();
  gl.uniform2f(nu.uResolution, w, h);
  gl.uniform1f(nu.uSeed, p.seed);
  gl.uniform1f(nu.uRoughness, p.roughness);
  gl.uniform3fv(nu.uColor, p.color);
  gl.uniform3fv(nu.uStarDir, p.starDir);
  gl.uniform2f(nu.uYawPitch, state.yaw, state.pitch);
  gl.uniform1f(nu.uFov, (70 * Math.PI) / 180);
  gl.uniform1i(nu.uSamples, samples);
  gl.uniform1i(nu.uIterations, iterations);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}

function drawStars(w, h) {
  if (starCount <= 0) return;
  gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.fbo);
  gl.viewport(0, 0, w, h);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.ONE, gl.ONE);
  gl.useProgram(starProg);
  gl.bindVertexArray(starVao);
  gl.uniform2f(su.uYawPitch, state.yaw, state.pitch);
  gl.uniform1f(su.uFov, (70 * Math.PI) / 180);
  gl.uniform2f(su.uResolution, w, h);
  gl.uniform1f(su.uPointScale, Math.max(w, h) / 900);
  gl.drawArrays(gl.POINTS, 0, starCount);
  gl.disable(gl.BLEND);
}

function blurPass(srcTex, dest, threshold) {
  gl.bindFramebuffer(gl.FRAMEBUFFER, dest.fbo);
  gl.viewport(0, 0, dest.w, dest.h);
  gl.disable(gl.BLEND);
  gl.useProgram(blurProg);
  gl.bindVertexArray(quadVao);
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, srcTex);
  gl.uniform1i(bu.uSrc, 0);
  gl.uniform2f(bu.uTexel, 1 / dest.w, 1 / dest.h);
  gl.uniform1f(bu.uThreshold, threshold);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}

function compositeTo(targetFbo, w, h) {
  gl.bindFramebuffer(gl.FRAMEBUFFER, targetFbo);
  gl.viewport(0, 0, w, h);
  gl.disable(gl.BLEND);
  gl.useProgram(compositeProg);
  gl.bindVertexArray(quadVao);
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, sceneTarget.tex);
  gl.uniform1i(cu.uScene, 0);
  gl.activeTexture(gl.TEXTURE1);
  gl.bindTexture(gl.TEXTURE_2D, bloomB.tex);
  gl.uniform1i(cu.uBloom, 1);
  gl.uniform1f(cu.uBloomStrength, 0.28);
  gl.uniform2f(cu.uResolution, w, h);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}

function gpuSync() {
  // finish() is unreliable on some SwiftShader paths; readPixels forces completion.
  const px = new Uint8Array(4);
  gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
}

function draw(w, h, samples, iterations) {
  ensureTargets(w, h);
  drawNebula(w, h, samples, iterations);
  drawStars(w, h);
  // Bloom chain: extract+blur → blur → blur
  blurPass(sceneTarget.tex, bloomA, 0.85);
  blurPass(bloomA.tex, bloomB, 0.0);
  blurPass(bloomB.tex, bloomA, 0.0);
  compositeTo(null, w, h);
  gpuSync();
}

function renderNow() {
  if (!state.params || state.rendering) return;
  state.rendering = true;
  const q = QUALITY[qualitySel.value] || QUALITY.good;
  resize(q.scale);
  const t0 = performance.now();
  try {
    draw(canvas.width, canvas.height, q.samples, q.iterations);
    const dt = performance.now() - t0;
    setStatus(
      `${canvas.width}×${canvas.height} · ${q.samples} samples · ${dt.toFixed(0)} ms`,
    );
    state.dirty = false;
    state.lastMs = performance.now();
  } catch (err) {
    console.error(err);
    setStatus(String(err.message || err));
  } finally {
    state.rendering = false;
  }
}

function frame() {
  if (state.dirty) renderNow();
  requestAnimationFrame(frame);
}

function downloadPng() {
  applySeedFromInput();
  const [ew, eh] = exportSel.value.split("x").map(Number);
  const q = QUALITY.high;
  setStatus(`Exporting ${ew}×${eh}…`);
  const prevW = canvas.width;
  const prevH = canvas.height;
  canvas.width = ew;
  canvas.height = eh;
  draw(ew, eh, q.samples, q.iterations);
  const a = document.createElement("a");
  a.download = `lt-sky_${state.params.seedStr.slice(0, 16)}_${ew}x${eh}.png`;
  a.href = canvas.toDataURL("image/png");
  a.click();
  canvas.width = prevW;
  canvas.height = prevH;
  state.dirty = true;
  setStatus(`Saved ${a.download}`);
}

canvas.addEventListener("pointerdown", (e) => {
  state.dragging = true;
  state.lastX = e.clientX;
  state.lastY = e.clientY;
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener("pointerup", () => {
  state.dragging = false;
});
canvas.addEventListener("pointercancel", () => {
  state.dragging = false;
});
canvas.addEventListener("pointermove", (e) => {
  if (!state.dragging) return;
  state.yaw += (e.clientX - state.lastX) * 0.005;
  state.pitch = Math.max(-1.2, Math.min(1.2, state.pitch - (e.clientY - state.lastY) * 0.005));
  state.lastX = e.clientX;
  state.lastY = e.clientY;
  state.dirty = true;
});

document.getElementById("render").addEventListener("click", () => {
  applySeedFromInput();
  renderNow();
});
document.getElementById("rand").addEventListener("click", () => {
  seedInput.value = randomSeedString();
  applySeedFromInput();
  renderNow();
});
document.getElementById("download").addEventListener("click", downloadPng);
seedInput.addEventListener("change", () => {
  applySeedFromInput();
  renderNow();
});
seedInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    applySeedFromInput();
    renderNow();
  }
});
qualitySel.addEventListener("change", () => {
  state.dirty = true;
  renderNow();
});
window.addEventListener("resize", () => {
  state.dirty = true;
});

try {
  applySeedFromInput();
  renderNow();
  requestAnimationFrame(frame);
} catch (err) {
  console.error(err);
  setStatus(String(err.message || err));
}
