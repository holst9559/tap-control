const tapsEl = document.getElementById('taps');
const lastPourEl = document.getElementById('last-pour');

let tapsState = [];
let pouringTapIds = new Set();

function mlToLiters(ml) {
  return (Number(ml) || 0) / 1000;
}

function formatLiters(ml) {
  return `${mlToLiters(ml).toFixed(2)} L`;
}

function percentRemaining(tap) {
  if (!tap.capacity_ml || tap.capacity_ml <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, (tap.remaining_ml / tap.capacity_ml) * 100));
}

function renderTap(tap) {
  const pct = percentRemaining(tap);
  const pouring = pouringTapIds.has(tap.id);
  const low = pct <= 15;

  const card = document.createElement('article');
  card.className = 'tap-card' + (pouring ? ' pouring' : '');
  card.dataset.tapId = String(tap.id);

  const label = document.createElement('div');
  label.className = 'tap-label';
  label.textContent = tap.name;

  const beer = document.createElement('h2');
  beer.className = 'beer-name';
  beer.textContent = tap.keg_name || 'No keg';

  const brewery = document.createElement('p');
  brewery.className = 'brewery';
  brewery.textContent = tap.keg_brewery || '';

  const meter = document.createElement('div');
  meter.className = 'meter';

  const bar = document.createElement('div');
  bar.className = 'meter-bar';

  const fill = document.createElement('div');
  fill.className = 'meter-fill' + (low ? ' low' : '');
  fill.style.width = `${pct}%`;

  const stats = document.createElement('div');
  stats.className = 'meter-stats';

  const left = document.createElement('span');
  left.textContent = tap.keg_id ? formatLiters(tap.remaining_ml) : '—';

  const right = document.createElement('span');
  right.textContent = tap.keg_id ? `${pct.toFixed(0)}%` : '';

  bar.appendChild(fill);
  stats.appendChild(left);
  stats.appendChild(right);
  meter.appendChild(bar);
  meter.appendChild(stats);

  card.appendChild(label);
  card.appendChild(beer);
  card.appendChild(brewery);
  card.appendChild(meter);

  return card;
}

function renderAll() {
  tapsEl.innerHTML = '';
  for (const tap of tapsState) {
    tapsEl.appendChild(renderTap(tap));
  }
}

function applyStatus(payload) {
  if (payload && payload.taps) {
    tapsState = payload.taps;
    renderAll();
  }
}

function onPourStart(payload) {
  pouringTapIds.add(payload.tapId);
  renderAll();
}

function onPourEnd(payload) {
  pouringTapIds.delete(payload.tapId);
  const liters = formatLiters(payload.volumeMl);
  lastPourEl.textContent = `Last pour · Tap ${payload.tapId} · ${liters}`;
  renderAll();
}

function handleWsMessage(event) {
  let message;
  try {
    message = JSON.parse(event.data);
  } catch (err) {
    return;
  }

  if (message.event === 'status') {
    applyStatus(message.payload);
    return;
  }

  if (message.event === 'pour_start') {
    onPourStart(message.payload);
    return;
  }

  if (message.event === 'pour_end') {
    onPourEnd(message.payload);
    return;
  }

  if (message.event === 'pour_update') {
    renderAll();
  }
}

function connectWs() {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const ws = new WebSocket(`${protocol}//${location.host}/ws`);
  ws.addEventListener('message', handleWsMessage);
  ws.addEventListener('close', scheduleReconnect);
}

function scheduleReconnect() {
  setTimeout(connectWs, 2000);
}

async function loadInitial() {
  try {
    const res = await fetch('/api/status');
    const data = await res.json();
    applyStatus(data);
  } catch (err) {
    lastPourEl.textContent = 'Unable to reach server';
  }
}

loadInitial();
connectWs();
