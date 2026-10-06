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

function formatPourVolume(ml) {
  const value = Number(ml) || 0;
  if (value < 1000) {
    return `${Math.round(value)} ml`;
  }
  return formatLiters(value);
}

function formatPourTime(iso) {
  if (!iso) {
    return '—';
  }

  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }

  return date.toLocaleString('sv-SE', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function percentRemaining(tap) {
  if (!tap.capacity_ml || tap.capacity_ml <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, (tap.remaining_ml / tap.capacity_ml) * 100));
}

function renderPourHistory(pours) {
  const history = document.createElement('div');
  history.className = 'pour-history';

  const title = document.createElement('div');
  title.className = 'pour-history-title';
  title.textContent = 'Senaste tappningar';
  history.appendChild(title);

  const list = document.createElement('ul');
  list.className = 'pour-history-list';

  if (!pours || pours.length === 0) {
    const empty = document.createElement('li');
    empty.className = 'pour-history-empty';
    empty.textContent = 'Inga tappningar ännu';
    list.appendChild(empty);
    history.appendChild(list);
    return history;
  }

  for (const pour of pours) {
    const row = document.createElement('li');
    row.className = 'pour-row';

    const time = document.createElement('time');
    time.dateTime = pour.ended_at || pour.started_at || '';
    time.textContent = formatPourTime(pour.ended_at || pour.started_at);

    const volume = document.createElement('span');
    volume.className = 'pour-volume';
    volume.textContent = formatPourVolume(pour.volume_ml);

    row.appendChild(time);
    row.appendChild(volume);
    list.appendChild(row);
  }

  history.appendChild(list);
  return history;
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
  beer.textContent = tap.keg_name || 'Inget fat';

  const brewery = document.createElement('p');
  brewery.className = 'brewery';
  brewery.textContent = tap.keg_brewery || '';

  const history = renderPourHistory(tap.recent_pours || []);

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
  card.appendChild(history);
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
  lastPourEl.textContent = `Senaste tappning · Kran ${payload.tapId} · ${liters}`;
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
    return;
  }

  if (message.event === 'settings' && message.payload) {
    applyTheme(message.payload.ui_theme);
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

async function loadSettingsTheme() {
  try {
    const res = await fetch('/api/settings');
    const data = await res.json();
    applyTheme(data.ui_theme);
  } catch (err) {
    applyTheme(DEFAULT_THEME);
  }
}

async function loadInitial() {
  try {
    const res = await fetch('/api/status');
    const data = await res.json();
    applyStatus(data);
  } catch (err) {
    lastPourEl.textContent = 'Kan inte nå servern';
  }
}

loadSettingsTheme();
loadInitial();
connectWs();
