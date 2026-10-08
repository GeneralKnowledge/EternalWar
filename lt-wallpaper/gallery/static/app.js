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
};

function randomSeed() {
  const hi = Math.floor(Math.random() * 9e15);
  const lo = Math.floor(Math.random() * 1e6);
  return String(hi) + String(lo).padStart(6, "0");
}

async function api(path, opts) {
  const res = await fetch(path, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(data.error || res.statusText);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function setStatus(msg) {
  els.status.textContent = msg;
}

function renderRate(status) {
  if (!status) {
    els.rate.textContent = "";
    return;
  }
  if (status.busy) {
    const age = status.busyForSec != null ? ` (${status.busyForSec}s)` : "";
    els.rate.textContent = `Bake in progress${age}…`;
    els.generate.disabled = true;
    // Keep the footer honest — "Ready" under a disabled button is confusing.
    if (!els.status.dataset.baking) {
      setStatus(
        "Generate locked — a bake is still running on the server. " +
          "On a 1 GiB host this can take several minutes (especially Best of > 1 or Belt/Planet). " +
          "If it never finishes: sudo systemctl restart lt-wallpaper-gallery",
      );
    }
    return;
  }
  if (status.retryAfterSec > 0) {
    els.rate.textContent = `Next bake in ${status.retryAfterSec}s`;
    els.generate.disabled = true;
    if (!els.status.dataset.baking) {
      setStatus(
        `Generate locked — rate limit (1 bake / ${status.limitSec}s). Wait ${status.retryAfterSec}s, then try again.`,
      );
    }
    return;
  }
  els.rate.textContent = `Ready · 1 bake / ${status.limitSec}s`;
  els.generate.disabled = false;
  if (!els.status.dataset.baking && els.status.textContent.startsWith("Generate locked")) {
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

els.rand.addEventListener("click", () => {
  els.seed.value = randomSeed();
});

els.form.addEventListener("submit", async (e) => {
  e.preventDefault();
  if (els.generate.disabled) return;
  els.generate.disabled = true;
  els.status.dataset.baking = "1";
  const maxBatch = state.meta?.maxBatchCount || 8;
  const maxBest = state.meta?.maxBestCount || 8;
  let count = parseInt(els.count?.value || "1", 10);
  let best = parseInt(els.best?.value || "1", 10);
  if (!Number.isFinite(count) || count < 1) count = 1;
  if (!Number.isFinite(best) || best < 1) best = 1;
  if (count > maxBatch) count = maxBatch;
  if (best > maxBest) best = maxBest;
  // Best-of wins over multi-keep when both are set.
  if (best > 1) count = 1;
  setStatus(
    best > 1
      ? `Baking ${best} candidates — keeping the best… (can take several minutes on small hosts)`
      : count > 1
        ? `Baking ${count} plates in one engine launch…`
        : "Baking with native ltheory… this can take a few minutes on 1 GiB.",
  );
  try {
    const data = await api("/api/generate", {
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
    delete els.status.dataset.baking;
    if (data.items && data.items.length > 1) {
      setStatus(`Saved ${data.items.length} plates (${data.items[0].width}×${data.items[0].height}).`);
    } else if (data.item) {
      const scoreBit =
        data.item.bestOf > 1
          ? ` · best of ${data.item.bestOf} (score ${data.item.score})`
          : "";
      setStatus(
        `Saved ${data.item.label} (${data.item.width}×${data.item.height})${scoreBit}.`,
      );
      if (!els.seed.value.trim()) els.seed.value = data.item.seed;
    }
    renderRate(data);
    await refreshGallery();
  } catch (err) {
    delete els.status.dataset.baking;
    const detail = err.data?.lastError ? ` — ${err.data.lastError}` : "";
    setStatus((err.message || "Generate failed") + detail);
    if (err.data) renderRate(err.data);
  } finally {
    delete els.status.dataset.baking;
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
});
