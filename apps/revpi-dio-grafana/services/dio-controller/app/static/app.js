const connection = document.querySelector("#connection");
const inputsEl = document.querySelector("#inputs");
const outputsEl = document.querySelector("#outputs");
const countersEl = document.querySelector("#counters");
const inputCountEl = document.querySelector("#input-count");
const outputCountEl = document.querySelector("#output-count");
const counterCountEl = document.querySelector("#counter-count");

let latest = null;
let busyOutputs = new Set();

function sortedEntries(value) {
  return Object.entries(value || {}).sort(([left], [right]) =>
    left.localeCompare(right, undefined, { numeric: true })
  );
}

function setConnection(online) {
  connection.textContent = online ? "Online" : "Offline";
  connection.classList.toggle("online", online);
  connection.classList.toggle("offline", !online);
}

function renderInputs(inputs) {
  const entries = sortedEntries(inputs);
  inputCountEl.textContent = entries.length;
  inputsEl.innerHTML = "";
  if (entries.length === 0) {
    inputsEl.innerHTML = '<div class="empty">No inputs</div>';
    return;
  }
  for (const [name, item] of entries) {
    const state = Number(item.state) === 1;
    const tile = document.createElement("article");
    tile.className = "tile";
    tile.innerHTML = `
      <div class="tile-row">
        <span class="name"></span>
        <span class="pill ${state ? "on" : "off"}">${state ? "ON" : "OFF"}</span>
      </div>
    `;
    tile.querySelector(".name").textContent = name;
    inputsEl.append(tile);
  }
}

function renderOutputs(outputs) {
  const entries = sortedEntries(outputs);
  outputCountEl.textContent = entries.length;
  outputsEl.innerHTML = "";
  if (entries.length === 0) {
    outputsEl.innerHTML = '<div class="empty">No outputs</div>';
    return;
  }
  for (const [name, item] of entries) {
    const state = Number(item.state) === 1;
    const tile = document.createElement("article");
    const id = `output-${name.replace(/[^a-z0-9_-]/gi, "-")}`;
    tile.className = "tile";
    tile.innerHTML = `
      <div class="tile-row">
        <span class="name"></span>
        <label class="switch" for="${id}">
          <input id="${id}" type="checkbox" ${state ? "checked" : ""}>
          <span class="track"></span>
        </label>
      </div>
    `;
    tile.querySelector(".name").textContent = name;
    const input = tile.querySelector("input");
    input.disabled = busyOutputs.has(name);
    input.addEventListener("change", () => setOutput(name, input.checked));
    outputsEl.append(tile);
  }
}

function renderCounters(counters) {
  const entries = sortedEntries(counters);
  counterCountEl.textContent = entries.length;
  countersEl.innerHTML = "";
  if (entries.length === 0) {
    countersEl.innerHTML = '<div class="empty">No counters</div>';
    return;
  }
  for (const [name, item] of entries) {
    const tile = document.createElement("article");
    tile.className = "tile metric";
    tile.innerHTML = `
      <div class="tile-row">
        <span class="name"></span>
        <span class="pill on">${Number(item.delta || 0)}</span>
      </div>
      <div class="metric-value">${Number(item.value || 0).toLocaleString()}</div>
      <div class="metric-detail">
        <span>${Number(item.delta || 0).toLocaleString()} since last sample</span>
      </div>
    `;
    tile.querySelector(".name").textContent = name;
    countersEl.append(tile);
  }
}

function render(data) {
  latest = data;
  renderInputs(data.inputs);
  renderOutputs(data.outputs);
  renderCounters(data.counters);
}

async function refresh() {
  try {
    const response = await fetch("/api/state", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    render(await response.json());
    setConnection(true);
  } catch (error) {
    setConnection(false);
    if (!latest) {
      inputsEl.innerHTML = '<div class="empty">No data</div>';
      outputsEl.innerHTML = '<div class="empty">No data</div>';
      countersEl.innerHTML = '<div class="empty">No data</div>';
    }
  }
}

async function setOutput(name, state) {
  busyOutputs.add(name);
  renderOutputs((latest && latest.outputs) || {});
  try {
    const response = await fetch(`/api/outputs/${encodeURIComponent(name)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ state }),
    });
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      throw new Error(payload.error || `HTTP ${response.status}`);
    }
    await refresh();
  } catch (error) {
    window.alert(error.message);
    await refresh();
  } finally {
    busyOutputs.delete(name);
    renderOutputs((latest && latest.outputs) || {});
  }
}

refresh();
setInterval(refresh, 1000);
