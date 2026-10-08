const els = {
  cats: document.getElementById("cats"),
  filters: document.getElementById("filters"),
  gallery: document.getElementById("gallery"),
  form: document.getElementById("form"),
  seed: document.getElementById("seed"),
  size: document.getElementById("size"),
  quality: document.getElementById("quality"),
  count: document.getElementById("count"),
  best: document.getElementById("best"),
  generate: document.getElementById("generate"),
  rand: document.getElementById("rand"),
  status: document.getElementById("status"),
  rate: document.getElementById("rate"),
  progress: document.getElementById("progress"),
  progressBar: document.getElementById("progressBar"),
  progressLabel: document.getElementById("progressLabel"),
  errorBox: document.getElementById("errorBox"),
  lightbox: document.getElementById("lightbox"),
  lightImg: document.getElementById("lightImg"),
  lightMeta: document.getElementById("lightMeta"),
  lightDl: document.getElementById("lightDl"),
};

const state = {
  meta: null,
  category: "sky",
  filter: "all",
  items: [],
  polling: null,
  baking: false,
  activeJobId: null,
};

function randomSeed() {
  const hi = Math.floor(Math.random() * 9e15);
  const lo = Math.floor(Math.random() * 1e6);
  return String(hi) + String(lo).padStart(6, "0");
}

function formatElapsed(sec) {
  const s = Math.max(0, Number(sec) || 0);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m > 0 ? `${m}m ${r}s` : `${r}s`;
}

async function api(path, opts) {
  const res = await fetch(path, opts);
  const raw = await res.text();
  let data = {};
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch {
    data = { error: raw.slice(0, 400) || res.statusText || `HTTP ${res.status}` };
  }
  if (!res.ok) {
    const msg =
      data.error ||
      data.message ||
      res.statusText ||
      `HTTP ${res.status}`;
    const err = new Error(msg);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function setStatus(msg) {
  els.status.textContent = msg;
}

function hideError() {
  if (!els.errorBox) return;
  els.errorBox.hidden = true;
  els.errorBox.textContent = "";
}

function showError({ title, detail, hint, logTail }) {
  if (!els.errorBox) {
    setStatus(title + (detail ? ` — ${detail}` : ""));
    return;
  }
  els.errorBox.hidden = false;
  const blocks = [];
  blocks.push(`<strong>${escapeHtml(title)}</strong>`);
  if (detail) blocks.push(`<p class="err-detail">${escapeHtml(detail)}</p>`);
  if (hint) blocks.push(`<p class="err-hint">${escapeHtml(hint)}</p>`);
  if (logTail) {
    blocks.push(`<pre class="err-log">${escapeHtml(logTail)}</pre>`);
  }
  els.errorBox.innerHTML = blocks.join("");
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function setProgress({ visible, pct, label }) {
  if (!els.progress) return;
  els.progress.hidden = !visible;
  if (!visible) return;
  const p = Math.max(0, Math.min(100, Number(pct) || 0));
  if (els.progressBar) els.progressBar.style.width = `${p}%`;
  if (els.progressLabel) els.progressLabel.textContent = label || "";
  els.generate.classList.toggle("baking", visible);
}

function phaseLabel(job) {
  if (!job) return "Working…";
  const elapsed = formatElapsed(job.elapsedSec);
  const mode = job.mode ? ` · ${job.mode}` : "";
  const base = job.message || job.phase || "Working…";
  return `${base}${mode} · ${elapsed}`;
}

function renderRate(status) {
  if (!status) {
    els.rate.textContent = "";
    return;
  }
  if (state.baking) {
    const job = status.job;
    const age = status.busyForSec != null ? status.busyForSec : job?.elapsedSec;
    els.rate.textContent = `Baking… ${formatElapsed(age)}`;
    els.generate.disabled = true;
    if (job) {
      setProgress({
        visible: true,
        pct: job.progress ?? 10,
        label: phaseLabel(job),
      });
    }
    return;
  }
  if (status.busy) {
    const age = status.busyForSec != null ? ` (${status.busyForSec}s)` : "";
    els.rate.textContent = `Bake in progress${age}…`;
    els.generate.disabled = true;
    setProgress({
      visible: true,
      pct: status.job?.progress ?? 20,
      label: phaseLabel(status.job) || "Another bake is running on the server…",
    });
    setStatus(
      "Generate locked — a bake is still running. " +
        "On 1 GiB hosts this can take several minutes. " +
        "If stuck: sudo systemctl restart lt-wallpaper-gallery",
    );
    return;
  }
  if (status.retryAfterSec > 0) {
    els.rate.textContent = `Next bake in ${status.retryAfterSec}s`;
    els.generate.disabled = true;
    setProgress({ visible: false });
    setStatus(
      `Generate locked — rate limit (1 bake / ${status.limitSec}s). Wait ${status.retryAfterSec}s.`,
    );
    return;
  }
  els.rate.textContent = `Ready · 1 bake / ${status.limitSec}s`;
  els.generate.disabled = false;
  setProgress({ visible: false });
  if (els.status.textContent.startsWith("Generate locked")) {
    setStatus(
      `Ready — native wallpaper.sh (1 bake / ${status.limitSec || 60}s). Prefer Best of 1 on small hosts.`,
    );
  }
}

function renderCategories() {
  const cats = state.meta.categories;
  els.cats.innerHTML = "";
  for (const c of cats) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "cat";
    btn.role = "option";
    btn.dataset.id = c.id;
    btn.setAttribute("aria-selected", c.id === state.category ? "true" : "false");
    btn.innerHTML = `<strong>${c.label}</strong><span>${c.blurb}</span>`;
    btn.addEventListener("click", () => {
      state.category = c.id;
      renderCategories();
    });
    els.cats.appendChild(btn);
  }
}

function fillSelects() {
  const defaults = state.meta.defaults || {};
  els.size.innerHTML = "";
  for (const [key, dim] of Object.entries(state.meta.sizes)) {
    const opt = document.createElement("option");
    opt.value = key;
    opt.textContent = `${key} · ${dim.width}×${dim.height}`;
    if (key === (defaults.size || "1080p")) opt.selected = true;
    els.size.appendChild(opt);
  }
  els.quality.innerHTML = "";
  for (const [key, res] of Object.entries(state.meta.quality)) {
    const opt = document.createElement("option");
    opt.value = key;
    opt.textContent = `${key} · nebula ${res}`;
    if (key === (defaults.quality || "good")) opt.selected = true;
    els.quality.appendChild(opt);
  }
}

function renderFilters() {
  const ids = ["all", ...state.meta.categories.map((c) => c.id)];
  els.filters.innerHTML = "";
  for (const id of ids) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "chip";
    chip.textContent = id === "all" ? "All" : state.meta.categories.find((c) => c.id === id).label;
    chip.setAttribute("aria-pressed", id === state.filter ? "true" : "false");
    chip.addEventListener("click", () => {
      state.filter = id;
      renderFilters();
      renderGallery();
    });
    els.filters.appendChild(chip);
  }
}

function renderGallery() {
  const items =
    state.filter === "all"
      ? state.items
      : state.items.filter((i) => i.category === state.filter);

  els.gallery.innerHTML = "";
  if (!items.length) {
    const empty = document.createElement("p");
    empty.className = "empty";
    empty.textContent = "No wallpapers in this category yet — generate one above.";
    els.gallery.appendChild(empty);
    return;
  }

  for (const item of items) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "card";
    const cat =
      state.meta.categories.find((c) => c.id === item.category)?.label || item.category;
    btn.innerHTML = `
      <img src="/api/image/${item.id}" alt="${cat} wallpaper" loading="lazy" />
      <div class="meta">
        <strong>${cat}</strong>
        ${item.width}×${item.height} · seed ${String(item.seed).slice(0, 18)}
      </div>
    `;
    btn.addEventListener("click", () => openLightbox(item));
    els.gallery.appendChild(btn);
  }
}

function openLightbox(item) {
  const cat =
    state.meta.categories.find((c) => c.id === item.category)?.label || item.category;
  els.lightImg.src = `/api/image/${item.id}`;
  els.lightImg.alt = `${cat} · ${item.seed}`;
  els.lightMeta.textContent = `${cat} · ${item.width}×${item.height} · seed ${item.seed} · nebulaRes ${item.nebulaRes ?? "—"}`;
  els.lightDl.href = `/api/image/${item.id}`;
  els.lightDl.download = `lt_${item.category}_${String(item.seed).slice(0, 16)}.png`;
  els.lightbox.showModal();
}

async function refreshGallery() {
  const data = await api("/api/gallery");
  state.items = data.items || [];
  renderGallery();
}

async function refreshStatus() {
  try {
    const status = await api("/api/status");
    renderRate(status);
  } catch {
    /* ignore transient */
  }
}

function startStatusPoll() {
  if (state.polling) clearInterval(state.polling);
  state.polling = setInterval(refreshStatus, 1000);
}

async function pollJob(jobId) {
  const started = Date.now();
  const maxMs = ((state.meta?.bakeTimeoutSec || 600) + 120) * 1000;
  while (Date.now() - started < maxMs) {
    const job = await api(`/api/jobs/${jobId}`);
    setProgress({
      visible: true,
      pct: job.progress ?? 10,
      label: phaseLabel(job),
    });
    els.rate.textContent = `Baking… ${formatElapsed(job.elapsedSec)}`;
    setStatus(phaseLabel(job));

    if (job.status === "done") {
      return job;
    }
    if (job.status === "error") {
      const err = new Error(job.error || "Generate failed");
      err.data = job;
      err.status = 500;
      throw err;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("Timed out waiting for bake job — check server journals");
}

els.rand.addEventListener("click", () => {
  els.seed.value = randomSeed();
});

els.form.addEventListener("submit", async (e) => {
  e.preventDefault();
  if (els.generate.disabled || state.baking) return;

  hideError();
  state.baking = true;
  els.generate.disabled = true;
  els.generate.textContent = "Baking…";

  const maxBatch = state.meta?.maxBatchCount || 8;
  const maxBest = state.meta?.maxBestCount || 8;
  let count = parseInt(els.count?.value || "1", 10);
  let best = parseInt(els.best?.value || "1", 10);
  if (!Number.isFinite(count) || count < 1) count = 1;
  if (!Number.isFinite(best) || best < 1) best = 1;
  if (count > maxBatch) count = maxBatch;
  if (best > maxBest) best = maxBest;
  if (best > 1) count = 1;

  setProgress({
    visible: true,
    pct: 3,
    label: best > 1
      ? `Queuing best-of ${best}…`
      : count > 1
        ? `Queuing ${count} plates…`
        : "Queuing bake…",
  });
  setStatus("Starting bake job…");

  try {
    const started = await api("/api/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        category: state.category,
        seed: els.seed.value.trim(),
        size: els.size.value,
        quality: els.quality.value,
        count,
        best,
      }),
    });

    const jobId = started.jobId || started.job?.id;
    if (!jobId) {
      throw new Error("Server did not return a job id");
    }
    state.activeJobId = jobId;
    setProgress({
      visible: true,
      pct: started.job?.progress ?? 8,
      label: phaseLabel(started.job) || "Job accepted…",
    });

    const job = await pollJob(jobId);

    if (job.items && job.items.length > 1) {
      setStatus(`Saved ${job.items.length} plates (${job.items[0].width}×${job.items[0].height}).`);
    } else if (job.item) {
      const scoreBit =
        job.item.bestOf > 1
          ? ` · best of ${job.item.bestOf} (score ${job.item.score})`
          : "";
      setStatus(
        `Saved ${job.item.label} (${job.item.width}×${job.item.height})${scoreBit}.`,
      );
      if (!els.seed.value.trim()) els.seed.value = job.item.seed;
    } else {
      setStatus(job.message || "Bake complete.");
    }
    await refreshGallery();
  } catch (err) {
    const detail = err.data?.error || err.message || "Generate failed";
    const hint = err.data?.hint;
    const logTail = err.data?.logTail || err.data?.lastError;
    showError({
      title: err.status ? `Generate failed [${err.status}]` : "Generate failed",
      detail,
      hint,
      logTail,
    });
    setStatus("Generate failed — see details below.");
  } finally {
    state.baking = false;
    state.activeJobId = null;
    els.generate.textContent = "Generate";
    setProgress({ visible: false });
    await refreshStatus();
  }
});

async function boot() {
  state.meta = await api("/api/meta");
  if (els.count && state.meta.maxBatchCount) {
    els.count.max = String(state.meta.maxBatchCount);
  }
  if (els.best && state.meta.maxBestCount) {
    els.best.max = String(state.meta.maxBestCount);
  }
  renderCategories();
  fillSelects();
  renderFilters();
  await refreshGallery();
  await refreshStatus();
  startStatusPoll();
  const profileBit = state.meta.profile
    ? ` Profile: ${state.meta.profile}${state.meta.profileNote ? ` — ${state.meta.profileNote}` : ""}`
    : "";
  setStatus(
    `Ready — native wallpaper.sh (1 bake / ${state.meta.rateLimitSec || 60}s). Count keeps the process loaded.${profileBit}`,
  );
}

boot().catch((err) => {
  setStatus(`Failed to load: ${err.message}`);
  showError({ title: "Failed to load gallery", detail: err.message });
});
