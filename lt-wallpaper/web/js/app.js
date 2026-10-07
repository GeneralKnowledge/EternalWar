import { VERT, FRAG } from "./shaders.js";
import { deriveNebulaParams, randomSeedString } from "./rng.js";

const QUALITY = {
  draft: { samples: 24, iterations: 16, scale: 0.55 },
  good: { samples: 48, iterations: 24, scale: 0.85 },
  high: { samples: 96, iterations: 30, scale: 1.0 },
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

const program = link(VERT, FRAG);
const u = {};
for (const name of [
  "uResolution",
  "uSeed",
  "uRoughness",
  "uColor",
  "uStarDir",
  "uLutR",
  "uLutG",
  "uLutB",
  "uYawPitch",
  "uFov",
  "uSamples",
  "uIterations",
  "uTime",
]) {
  u[name] = gl.getUniformLocation(program, name);
}

const vao = gl.createVertexArray();
gl.bindVertexArray(vao);

const state = {
  yaw: -1.15,
  pitch: 0.12,
  params: deriveNebulaParams(seedInput.value),
  dragging: false,
  lastX: 0,
  lastY: 0,
  dirty: true,
  lastMs: 0,
};

function setStatus(msg) {
  statusEl.textContent = msg;
}

function applySeedFromInput() {
  state.params = deriveNebulaParams(seedInput.value.trim() || "0");
  state.dirty = true;
  setStatus(`Seed ${state.params.seedStr.slice(0, 18)}… · roughness ${state.params.roughness.toFixed(3)}`);
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

function draw(targetW, targetH, samples, iterations) {
  gl.viewport(0, 0, targetW, targetH);
  gl.useProgram(program);
  gl.bindVertexArray(vao);

  const p = state.params;
  gl.uniform2f(u.uResolution, targetW, targetH);
  gl.uniform1f(u.uSeed, p.seed);
  gl.uniform1f(u.uRoughness, p.roughness);
  gl.uniform3fv(u.uColor, p.color);
  gl.uniform3fv(u.uStarDir, p.starDir);
  gl.uniform3fv(u.uLutR, p.lutR);
  gl.uniform3fv(u.uLutG, p.lutG);
  gl.uniform3fv(u.uLutB, p.lutB);
  gl.uniform2f(u.uYawPitch, state.yaw, state.pitch);
  gl.uniform1f(u.uFov, (65 * Math.PI) / 180);
  gl.uniform1i(u.uSamples, samples);
  gl.uniform1i(u.uIterations, iterations);
  gl.uniform1f(u.uTime, performance.now() * 0.001);

  gl.drawArrays(gl.TRIANGLES, 0, 3);
}

function frame(now) {
  const q = QUALITY[qualitySel.value] || QUALITY.good;
  resize(q.scale);
  if (state.dirty || now - state.lastMs > 2000) {
    const t0 = performance.now();
    draw(canvas.width, canvas.height, q.samples, q.iterations);
    const dt = performance.now() - t0;
    setStatus(
      `${canvas.width}×${canvas.height} · ${q.samples} samples · ${dt.toFixed(0)} ms`,
    );
    state.dirty = false;
    state.lastMs = now;
  }
  requestAnimationFrame(frame);
}

function downloadPng() {
  const [ew, eh] = exportSel.value.split("x").map(Number);
  const q = QUALITY.high;
  setStatus(`Exporting ${ew}×${eh}…`);

  // Render offscreen at export resolution
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
  const dx = e.clientX - state.lastX;
  const dy = e.clientY - state.lastY;
  state.lastX = e.clientX;
  state.lastY = e.clientY;
  state.yaw += dx * 0.005;
  state.pitch = Math.max(-1.2, Math.min(1.2, state.pitch - dy * 0.005));
  state.dirty = true;
});

document.getElementById("render").addEventListener("click", () => {
  applySeedFromInput();
});
document.getElementById("rand").addEventListener("click", () => {
  seedInput.value = randomSeedString();
  applySeedFromInput();
});
document.getElementById("download").addEventListener("click", () => {
  applySeedFromInput();
  downloadPng();
});
seedInput.addEventListener("change", applySeedFromInput);
seedInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") applySeedFromInput();
});
qualitySel.addEventListener("change", () => {
  state.dirty = true;
});
window.addEventListener("resize", () => {
  state.dirty = true;
});

applySeedFromInput();
requestAnimationFrame(frame);
