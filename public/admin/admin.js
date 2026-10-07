const TOKEN_KEY = 'tap_control_cms_token';

const loginView = document.getElementById('login-view');
const appView = document.getElementById('app-view');
const loginForm = document.getElementById('login-form');
const loginError = document.getElementById('login-error');
const pinInput = document.getElementById('pin-input');
const logoutBtn = document.getElementById('logout-btn');

const liveTapsEl = document.getElementById('live-taps');
const poursBody = document.getElementById('pours-body');

const assignForm = document.getElementById('assign-form');
const assignTap = document.getElementById('assign-tap');
const assignMode = document.getElementById('assign-mode');
const existingKegWrap = document.getElementById('existing-keg-wrap');
const assignExisting = document.getElementById('assign-existing');
const assignName = document.getElementById('assign-name');
const assignCapacity = document.getElementById('assign-capacity');
const assignRemaining = document.getElementById('assign-remaining');
const assignPreviousStatus = document.getElementById('assign-previous-status');
const assignMsg = document.getElementById('assign-msg');

const editKegForm = document.getElementById('edit-keg-form');
const editKegId = document.getElementById('edit-keg-id');
const editName = document.getElementById('edit-name');
const editCapacity = document.getElementById('edit-capacity');
const editRemaining = document.getElementById('edit-remaining');
const editStatus = document.getElementById('edit-status');
const editNotes = document.getElementById('edit-notes');
const editMsg = document.getElementById('edit-msg');

const tapForm = document.getElementById('tap-form');
const tapId = document.getElementById('tap-id');
const tapName = document.getElementById('tap-name');
const tapPpl = document.getElementById('tap-ppl');
const tapSound = document.getElementById('tap-sound');
const tapMsg = document.getElementById('tap-msg');
const calStart = document.getElementById('cal-start');
const calCancel = document.getElementById('cal-cancel');
const calFinish = document.getElementById('cal-finish');
const calVolume = document.getElementById('cal-volume');
const calStatus = document.getElementById('cal-status');

const settingsForm = document.getElementById('settings-form');
const defaultSound = document.getElementById('default-sound');
const pourIdle = document.getElementById('pour-idle');
const displayUnits = document.getElementById('display-units');
const testSoundBtn = document.getElementById('test-sound');
const uploadForm = document.getElementById('upload-form');
const soundFileInput = document.getElementById('sound-file');
const pinForm = document.getElementById('pin-form');
const pinCurrent = document.getElementById('pin-current');
const pinNew = document.getElementById('pin-new');
const settingsMsg = document.getElementById('settings-msg');
const themeForm = document.getElementById('theme-form');
const uiTheme = document.getElementById('ui-theme');
const themeMsg = document.getElementById('theme-msg');

let token = localStorage.getItem(TOKEN_KEY) || '';
let taps = [];
let kegs = [];
let sounds = [];

function showMsg(el, text, isError) {
  el.hidden = false;
  el.textContent = text;
  el.classList.toggle('error', Boolean(isError));
}

function getToken() {
  return token;
}

function setToken(value) {
  token = value || '';
  if (token) {
    localStorage.setItem(TOKEN_KEY, token);
  } else {
    localStorage.removeItem(TOKEN_KEY);
  }
}

async function api(path, options) {
  const opts = options || {};
  const headers = Object.assign({}, opts.headers || {});

  if (!(opts.body instanceof FormData)) {
    headers['Content-Type'] = 'application/json';
  }

  if (token) {
    headers['X-CMS-Token'] = token;
  }

  const res = await fetch(`/api${path}`, {
    method: opts.method || 'GET',
    headers,
    body: opts.body,
  });

  let data = null;
  try {
    data = await res.json();
  } catch (err) {
    data = null;
  }

  if (!res.ok) {
    const message = data && data.error ? data.error : res.statusText;
    throw new Error(message);
  }

  return data;
}

function showLogin() {
  loginView.hidden = false;
  appView.hidden = true;
}

function showApp() {
  loginView.hidden = true;
  appView.hidden = false;
}

function fillSelect(select, items, getValue, getLabel, includeEmpty) {
  select.innerHTML = '';

  if (includeEmpty) {
    const empty = document.createElement('option');
    empty.value = '';
    empty.textContent = '— ingen —';
    select.appendChild(empty);
  }

  for (const item of items) {
    const option = document.createElement('option');
    option.value = String(getValue(item));
    option.textContent = getLabel(item);
    select.appendChild(option);
  }
}

function tapValue(tap) {
  return tap.id;
}

function tapLabel(tap) {
  return `${tap.name} (BCM ${tap.gpio_pin})`;
}

function kegValue(keg) {
  return keg.id;
}

function statusLabel(status) {
  if (status === 'on_tap') {
    return 'På kran';
  }
  if (status === 'stored') {
    return 'Lagrat';
  }
  if (status === 'empty') {
    return 'Tomt';
  }
  return status;
}

function kegLabel(keg) {
  return `${keg.name} · ${Math.round(keg.remaining_ml)}/${Math.round(keg.capacity_ml)} ml · ${statusLabel(keg.status)}`;
}

function soundValue(name) {
  return name;
}

function soundLabel(name) {
  return name;
}

function percent(tap) {
  if (!tap.capacity_ml) {
    return 0;
  }
  return Math.max(0, Math.min(100, (tap.remaining_ml / tap.capacity_ml) * 100));
}

function renderLiveTaps() {
  liveTapsEl.innerHTML = '';

  for (const tap of taps) {
    const card = document.createElement('div');
    card.className = 'tap-live';

    const title = document.createElement('div');
    title.className = 'muted';
    title.textContent = tap.name;

    const beer = document.createElement('strong');
    beer.textContent = tap.keg_name || 'Inget fat kopplat';

    const meta = document.createElement('div');
    meta.className = 'muted';
    meta.textContent = tap.keg_id
      ? `${Math.round(tap.remaining_ml)} ml kvar · ${percent(tap).toFixed(0)}%`
      : 'Koppla ett fat för att börja mäta';

    const bar = document.createElement('div');
    bar.className = 'bar';
    const fill = document.createElement('span');
    fill.style.width = `${percent(tap)}%`;
    bar.appendChild(fill);

    card.appendChild(title);
    card.appendChild(beer);
    card.appendChild(meta);
    card.appendChild(bar);
    liveTapsEl.appendChild(card);
  }
}

function renderPours(pours) {
  poursBody.innerHTML = '';

  for (const pour of pours) {
    const tr = document.createElement('tr');
    const when = document.createElement('td');
    when.textContent = new Date(pour.started_at).toLocaleString('sv-SE');

    const tapCell = document.createElement('td');
    tapCell.textContent = pour.tap_name || `Kran ${pour.tap_id}`;

    const beer = document.createElement('td');
    beer.textContent = pour.keg_name || '—';

    const volume = document.createElement('td');
    volume.textContent = `${Math.round(pour.volume_ml)} ml`;

    tr.appendChild(when);
    tr.appendChild(tapCell);
    tr.appendChild(beer);
    tr.appendChild(volume);
    poursBody.appendChild(tr);
  }
}

function refreshSelects() {
  fillSelect(assignTap, taps, tapValue, tapLabel, false);
  fillSelect(tapId, taps, tapValue, tapLabel, false);
  fillSelect(assignExisting, kegs, kegValue, kegLabel, false);
  fillSelect(editKegId, kegs, kegValue, kegLabel, false);

  fillSelect(tapSound, sounds, soundValue, soundLabel, true);
  fillSelect(defaultSound, sounds, soundValue, soundLabel, true);

  syncTapForm();
  syncEditKegForm();
}

function findTapById(id) {
  for (const tap of taps) {
    if (tap.id === id) {
      return tap;
    }
  }
  return null;
}

function findKegById(id) {
  for (const keg of kegs) {
    if (keg.id === id) {
      return keg;
    }
  }
  return null;
}

function syncTapForm() {
  const tap = findTapById(Number(tapId.value));
  if (!tap) {
    return;
  }

  tapName.value = tap.name;
  tapPpl.value = tap.pulses_per_liter;
  tapSound.value = tap.sound_file || '';
}

function syncEditKegForm() {
  const keg = findKegById(Number(editKegId.value));
  if (!keg) {
    return;
  }

  editName.value = keg.name;
  editCapacity.value = Math.round(keg.capacity_ml);
  editRemaining.value = Math.round(keg.remaining_ml);
  editStatus.value = keg.status;
  editNotes.value = keg.notes || '';
}

function syncAssignMode() {
  const existing = assignMode.value === 'existing';
  existingKegWrap.hidden = !existing;
  assignName.disabled = existing;
  assignCapacity.disabled = existing;
  assignRemaining.disabled = existing;
}

async function refreshAll() {
  const status = await api('/status');
  const kegData = await api('/kegs');
  const soundData = await api('/sounds');
  const settings = await api('/settings');
  const pourData = await api('/pours?limit=40');

  taps = status.taps || [];
  kegs = kegData.kegs || [];
  sounds = soundData.sounds || [];

  pourIdle.value = settings.pour_idle_ms;
  displayUnits.value = settings.display_units || 'liters';
  defaultSound.value = settings.default_sound_file || '';
  fillThemeSelect(uiTheme, settings.ui_theme);
  applyTheme(settings.ui_theme);

  refreshSelects();
  renderLiveTaps();
  renderPours(pourData.pours || []);
}

async function onLoginSubmit(event) {
  event.preventDefault();
  loginError.hidden = true;

  try {
    const data = await api('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ pin: pinInput.value }),
    });
    setToken(data.token);
    showApp();
    await refreshAll();
    connectWs();
  } catch (err) {
    loginError.hidden = false;
    loginError.textContent = err.message;
  }
}

async function onLogout() {
  try {
    await api('/auth/logout', { method: 'POST', body: JSON.stringify({}) });
  } catch (err) {
    // ignore
  }
  setToken('');
  showLogin();
}

async function onAssignSubmit(event) {
  event.preventDefault();

  try {
    let body;

    if (assignMode.value === 'existing') {
      body = {
        keg_id: Number(assignExisting.value),
        previous_status: assignPreviousStatus.value,
      };
    } else {
      body = {
        create: true,
        name: assignName.value,
        capacity_ml: Number(assignCapacity.value),
        remaining_ml: Number(assignRemaining.value),
        previous_status: assignPreviousStatus.value,
      };
    }

    await api(`/taps/${assignTap.value}/assign-keg`, {
      method: 'POST',
      body: JSON.stringify(body),
    });

    showMsg(assignMsg, 'Fat kopplat', false);
    await refreshAll();
  } catch (err) {
    showMsg(assignMsg, err.message, true);
  }
}

async function onEditKegSubmit(event) {
  event.preventDefault();

  try {
    await api(`/kegs/${editKegId.value}`, {
      method: 'PATCH',
      body: JSON.stringify({
        name: editName.value,
        capacity_ml: Number(editCapacity.value),
        remaining_ml: Number(editRemaining.value),
        status: editStatus.value,
        notes: editNotes.value,
      }),
    });
    showMsg(editMsg, 'Fat sparat', false);
    await refreshAll();
  } catch (err) {
    showMsg(editMsg, err.message, true);
  }
}

async function onTapSubmit(event) {
  event.preventDefault();

  try {
    await api(`/taps/${tapId.value}`, {
      method: 'PATCH',
      body: JSON.stringify({
        name: tapName.value,
        pulses_per_liter: Number(tapPpl.value),
        sound_file: tapSound.value || null,
      }),
    });
    showMsg(tapMsg, 'Kran sparad', false);
    await refreshAll();
  } catch (err) {
    showMsg(tapMsg, err.message, true);
  }
}

async function onCalStart() {
  try {
    await api(`/taps/${tapId.value}/calibration/start`, {
      method: 'POST',
      body: JSON.stringify({}),
    });
    calStatus.textContent = 'Kalibrering aktiv — tappa en känd volym nu';
  } catch (err) {
    calStatus.textContent = err.message;
  }
}

async function onCalCancel() {
  try {
    await api(`/taps/${tapId.value}/calibration/cancel`, {
      method: 'POST',
      body: JSON.stringify({}),
    });
    calStatus.textContent = 'Kalibrering avbruten';
  } catch (err) {
    calStatus.textContent = err.message;
  }
}

async function onCalFinish() {
  try {
    const result = await api(`/taps/${tapId.value}/calibration/finish`, {
      method: 'POST',
      body: JSON.stringify({ known_volume_ml: Number(calVolume.value) }),
    });
    calStatus.textContent = `Sparade ${result.pulsesPerLiter.toFixed(1)} pulser/L från ${result.pulseCount} pulser`;
    await refreshAll();
  } catch (err) {
    calStatus.textContent = err.message;
  }
}

async function onSettingsSubmit(event) {
  event.preventDefault();

  try {
    await api('/settings', {
      method: 'PUT',
      body: JSON.stringify({
        pour_idle_ms: Number(pourIdle.value),
        default_sound_file: defaultSound.value,
        display_units: displayUnits.value,
      }),
    });
    showMsg(settingsMsg, 'Inställningar sparade', false);
  } catch (err) {
    showMsg(settingsMsg, err.message, true);
  }
}

function onThemePreview() {
  applyTheme(uiTheme.value);
}

async function onThemeSubmit(event) {
  event.preventDefault();

  try {
    const settings = await api('/settings', {
      method: 'PUT',
      body: JSON.stringify({
        ui_theme: uiTheme.value,
      }),
    });
    applyTheme(settings.ui_theme);
    fillThemeSelect(uiTheme, settings.ui_theme);
    showMsg(themeMsg, 'Tema tillämpat på kiosk & CMS', false);
  } catch (err) {
    showMsg(themeMsg, err.message, true);
  }
}

async function onTestSound() {
  try {
    await api('/sounds/test', {
      method: 'POST',
      body: JSON.stringify({ sound_file: defaultSound.value }),
    });
    showMsg(settingsMsg, 'Uppspelning begärd', false);
  } catch (err) {
    showMsg(settingsMsg, err.message, true);
  }
}

async function onUploadSubmit(event) {
  event.preventDefault();

  const file = soundFileInput.files[0];
  if (!file) {
    return;
  }

  const body = new FormData();
  body.append('file', file);

  try {
    const data = await api('/sounds', { method: 'POST', body });
    sounds = data.sounds || [];
    refreshSelects();
    defaultSound.value = data.sound;
    showMsg(settingsMsg, `Uppladdad ${data.sound}`, false);
    uploadForm.reset();
  } catch (err) {
    showMsg(settingsMsg, err.message, true);
  }
}

async function onPinSubmit(event) {
  event.preventDefault();

  try {
    await api('/auth/pin', {
      method: 'POST',
      body: JSON.stringify({
        current_pin: pinCurrent.value,
        new_pin: pinNew.value,
      }),
    });
    pinForm.reset();
    showMsg(settingsMsg, 'PIN uppdaterad', false);
  } catch (err) {
    showMsg(settingsMsg, err.message, true);
  }
}

function onWsMessage(event) {
  let message;
  try {
    message = JSON.parse(event.data);
  } catch (err) {
    return;
  }

  if (message.event === 'status' && message.payload && message.payload.taps) {
    taps = message.payload.taps;
    renderLiveTaps();
    refreshSelects();
    return;
  }

  if (message.event === 'kegs_changed' && message.payload && message.payload.kegs) {
    kegs = message.payload.kegs;
    refreshSelects();
    return;
  }

  if (message.event === 'calibration_pulse') {
    calStatus.textContent = `Kalibreringspulser: ${message.payload.pulseCount}`;
    return;
  }

  if (message.event === 'pour_end') {
    refreshPours();
    return;
  }

  if (message.event === 'settings' && message.payload) {
    applyTheme(message.payload.ui_theme);
    if (uiTheme) {
      fillThemeSelect(uiTheme, message.payload.ui_theme);
    }
  }
}

async function refreshPours() {
  try {
    const pourData = await api('/pours?limit=40');
    renderPours(pourData.pours || []);
  } catch (err) {
    // ignore transient errors
  }
}

function scheduleReconnect() {
  setTimeout(connectWs, 2000);
}

function connectWs() {
  if (!getToken()) {
    return;
  }

  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const ws = new WebSocket(`${protocol}//${location.host}/ws`);
  ws.addEventListener('message', onWsMessage);
  ws.addEventListener('close', scheduleReconnect);
}

async function loadPublicTheme() {
  try {
    const res = await fetch('/api/settings');
    const settings = await res.json();
    fillThemeSelect(uiTheme, settings.ui_theme);
    applyTheme(settings.ui_theme);
  } catch (err) {
    fillThemeSelect(uiTheme, DEFAULT_THEME);
    applyTheme(DEFAULT_THEME);
  }
}

async function boot() {
  loginForm.addEventListener('submit', onLoginSubmit);
  logoutBtn.addEventListener('click', onLogout);
  assignForm.addEventListener('submit', onAssignSubmit);
  assignMode.addEventListener('change', syncAssignMode);
  editKegForm.addEventListener('submit', onEditKegSubmit);
  editKegId.addEventListener('change', syncEditKegForm);
  tapForm.addEventListener('submit', onTapSubmit);
  tapId.addEventListener('change', syncTapForm);
  calStart.addEventListener('click', onCalStart);
  calCancel.addEventListener('click', onCalCancel);
  calFinish.addEventListener('click', onCalFinish);
  settingsForm.addEventListener('submit', onSettingsSubmit);
  themeForm.addEventListener('submit', onThemeSubmit);
  uiTheme.addEventListener('change', onThemePreview);
  testSoundBtn.addEventListener('click', onTestSound);
  uploadForm.addEventListener('submit', onUploadSubmit);
  pinForm.addEventListener('submit', onPinSubmit);

  syncAssignMode();
  await loadPublicTheme();

  if (!token) {
    showLogin();
    return;
  }

  try {
    await refreshAll();
    showApp();
    connectWs();
  } catch (err) {
    setToken('');
    showLogin();
  }
}

boot();
