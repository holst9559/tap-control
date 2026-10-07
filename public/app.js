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

/** Shown when the counter hits 0 — there may still be beer in the lines. */
const EMPTY_KEG_LINES = [
  'Inte många droppar kvar nu',
  'Meddela närmsta servicetekniker',
  'Nu vart det slut',
  'Fatet säger nej. Röret säger kanske.',
  'Servicetekniker till baren, tack',
  'Ring bryggmästaren — vi är på reserv',
];

function emptyKegLine(tap) {
  const key = `${tap.keg_id || 0}:${tap.id}`;
  let hash = 0;
  for (let i = 0; i < key.length; i += 1) {
    hash = (hash + key.charCodeAt(i) * (i + 1)) % EMPTY_KEG_LINES.length;
  }
  return EMPTY_KEG_LINES[hash];
}

function isKegCounterEmpty(tap) {
  return Boolean(tap.keg_id) && Number(tap.remaining_ml) <= 0;
}

function pourHistoryKey(pours) {
  if (!pours || pours.length === 0) {
    return '';
  }
  let key = '';
  for (const pour of pours) {
    key += `${pour.id}:${pour.volume_ml};`;
  }
  return key;
}

function fillPourHistoryList(list, pours) {
  list.innerHTML = '';

  if (!pours || pours.length === 0) {
    const empty = document.createElement('li');
    empty.className = 'pour-history-empty';
    empty.textContent = 'Inga tappningar ännu';
    list.appendChild(empty);
    return;
  }

  pours.forEach((pour, index) => {
    const row = document.createElement('li');
    row.className = 'pour-row' + (index % 2 === 0 ? ' pour-row--a' : ' pour-row--b');

    const time = document.createElement('time');
    time.dateTime = pour.ended_at || pour.started_at || '';
    time.textContent = formatPourTime(pour.ended_at || pour.started_at);

    const volume = document.createElement('span');
    volume.className = 'pour-volume';
    volume.textContent = formatPourVolume(pour.volume_ml);

    row.appendChild(time);
    row.appendChild(volume);
    list.appendChild(row);
  });
}

function createTapCard(tap) {
  const card = document.createElement('article');
  card.className = 'tap-card';
  card.dataset.tapId = String(tap.id);
  card.dataset.historyKey = '';

  const head = document.createElement('div');
  head.className = 'tap-head';

  const label = document.createElement('div');
  label.className = 'tap-label';

  const beer = document.createElement('h2');
  beer.className = 'beer-name';

  head.appendChild(label);
  head.appendChild(beer);

  const history = document.createElement('div');
  history.className = 'pour-history';

  const historyTitle = document.createElement('div');
  historyTitle.className = 'pour-history-title';
  historyTitle.textContent = 'Senaste tappningar';

  const historyList = document.createElement('ul');
  historyList.className = 'pour-history-list';

  history.appendChild(historyTitle);
  history.appendChild(historyList);

  const meter = document.createElement('div');
  meter.className = 'meter';

  const bar = document.createElement('div');
  bar.className = 'meter-bar';

  const fill = document.createElement('div');
  fill.className = 'meter-fill';

  const stats = document.createElement('div');
  stats.className = 'meter-stats';

  const left = document.createElement('span');
  left.className = 'meter-left';

  const right = document.createElement('span');
  right.className = 'meter-right';

  const emptyMsg = document.createElement('p');
  emptyMsg.className = 'meter-empty-msg';
  emptyMsg.hidden = true;

  bar.appendChild(fill);
  stats.appendChild(left);
  stats.appendChild(right);
  meter.appendChild(emptyMsg);
  meter.appendChild(bar);
  meter.appendChild(stats);

  card.appendChild(head);
  card.appendChild(history);
  card.appendChild(meter);

  return card;
}

function updateTapCard(card, tap) {
  const pct = percentRemaining(tap);
  const pouring = pouringTapIds.has(tap.id);
  const low = pct <= 15;
  const empty = isKegCounterEmpty(tap);
  const historyKey = pourHistoryKey(tap.recent_pours);

  card.className = 'tap-card' + (pouring ? ' pouring' : '') + (empty ? ' tap-empty' : '');
  card.querySelector('.tap-label').textContent = tap.name;
  card.querySelector('.beer-name').textContent = tap.keg_name || 'Inget fat';

  if (card.dataset.historyKey !== historyKey) {
    fillPourHistoryList(card.querySelector('.pour-history-list'), tap.recent_pours || []);
    card.dataset.historyKey = historyKey;
  }

  const meter = card.querySelector('.meter');
  const emptyMsg = card.querySelector('.meter-empty-msg');
  const fill = card.querySelector('.meter-fill');

  if (empty) {
    meter.classList.add('meter--empty');
    emptyMsg.hidden = false;
    emptyMsg.textContent = emptyKegLine(tap);
    fill.className = 'meter-fill meter-fill--empty';
    fill.style.width = '100%';
    card.querySelector('.meter-left').textContent = formatLiters(0);
    card.querySelector('.meter-right').textContent = '0%';
    return;
  }

  meter.classList.remove('meter--empty');
  emptyMsg.hidden = true;
  emptyMsg.textContent = '';

  fill.className = 'meter-fill' + (low ? ' low' : '');
  fill.style.width = `${pct}%`;

  card.querySelector('.meter-left').textContent = tap.keg_id ? formatLiters(tap.remaining_ml) : '—';
  card.querySelector('.meter-right').textContent = tap.keg_id ? `${pct.toFixed(0)}%` : '';
}

function renderAll() {
  const seen = new Set();

  for (const tap of tapsState) {
    seen.add(String(tap.id));
    let card = tapsEl.querySelector(`[data-tap-id="${tap.id}"]`);
    if (!card) {
      card = createTapCard(tap);
      tapsEl.appendChild(card);
    }
    updateTapCard(card, tap);
  }

  const cards = tapsEl.querySelectorAll('.tap-card');
  for (const card of cards) {
    if (!seen.has(card.dataset.tapId)) {
      card.remove();
    }
  }
}

function findTap(tapId) {
  for (const tap of tapsState) {
    if (tap.id === tapId) {
      return tap;
    }
  }
  return null;
}

function applyStatus(payload) {
  if (payload && payload.taps) {
    tapsState = payload.taps;
    renderAll();
  }
}

function onPourStart(payload) {
  pouringTapIds.add(payload.tapId);
  const tap = findTap(payload.tapId);
  if (!tap) {
    return;
  }
  const card = tapsEl.querySelector(`[data-tap-id="${tap.id}"]`);
  if (card) {
    updateTapCard(card, tap);
  }
}

function onPourUpdate(payload) {
  const tap = findTap(payload.tapId);
  if (!tap) {
    return;
  }

  if (payload.remainingMl != null) {
    tap.remaining_ml = payload.remainingMl;
  }
  if (payload.capacityMl != null) {
    tap.capacity_ml = payload.capacityMl;
  }

  pouringTapIds.add(payload.tapId);
  const card = tapsEl.querySelector(`[data-tap-id="${tap.id}"]`);
  if (card) {
    updateTapCard(card, tap);
  }
}

function onPourEnd(payload) {
  pouringTapIds.delete(payload.tapId);
  const liters = formatLiters(payload.volumeMl);
  lastPourEl.textContent = `Senaste tappning · Kran ${payload.tapId} · ${liters}`;
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
    onPourUpdate(message.payload);
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
