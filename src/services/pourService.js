const config = require('../config');
const { getDb, getSetting } = require('../db/client');
const kegService = require('./kegService');
const soundService = require('./soundService');
const hub = require('../ws/hub');

const activePours = new Map();
const pendingPours = new Map();
const idleTimers = new Map();
const calibrationSessions = new Map();

function getPourIdleMs() {
  const raw = getSetting('pour_idle_ms');
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 500) {
    return config.defaultPourIdleMs;
  }
  return value;
}

function getMinPourMl() {
  const raw = getSetting('min_pour_ml');
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    return config.defaultMinPourMl;
  }
  return value;
}

function pulsesToMl(pulses, pulsesPerLiter) {
  if (!pulsesPerLiter || pulsesPerLiter <= 0) {
    return 0;
  }
  return (pulses / pulsesPerLiter) * 1000;
}

function clearIdleTimer(tapId) {
  const timer = idleTimers.get(tapId);
  if (timer) {
    clearTimeout(timer);
    idleTimers.delete(tapId);
  }
}

function createPendingPour(tapId) {
  const tap = kegService.getTap(tapId);
  if (!tap) {
    return null;
  }

  return {
    tapId,
    kegId: tap.keg_id,
    startedAt: new Date().toISOString(),
    pulseCount: 0,
    volumeMl: 0,
    pulsesPerLiter: tap.pulses_per_liter,
    lastReportedVolumeMl: 0,
    id: null,
  };
}

// Persist + notify once volume clears the minimum. Keep this path light:
// a full status broadcast here (mid-pour) blocks the event loop on Pi and
// pigpio drops pulses — which is how a 350ml pour became ~11ml.
function commitPour(pour) {
  const db = getDb();
  const result = db
    .prepare(
      `
    INSERT INTO pours (tap_id, keg_id, started_at, ended_at, volume_ml, pulse_count)
    VALUES (?, ?, ?, NULL, ?, ?)
  `,
    )
    .run(pour.tapId, pour.kegId, pour.startedAt, pour.volumeMl, pour.pulseCount);

  pour.id = result.lastInsertRowid;
  activePours.set(pour.tapId, pour);
  pendingPours.delete(pour.tapId);

  soundService.playPourSound(pour.tapId);

  hub.broadcast('pour_start', {
    tapId: pour.tapId,
    pourId: pour.id,
    kegId: pour.kegId,
    startedAt: pour.startedAt,
  });
}

function updateActivePour(tapId) {
  const pour = activePours.get(tapId);
  if (!pour) {
    return null;
  }

  pour.volumeMl = pulsesToMl(pour.pulseCount, pour.pulsesPerLiter);

  const db = getDb();
  db.prepare(
    `
    UPDATE pours
    SET volume_ml = ?, pulse_count = ?
    WHERE id = ?
  `,
  ).run(pour.volumeMl, pour.pulseCount, pour.id);

  const deltaMl = pour.volumeMl - pour.lastReportedVolumeMl;
  if (deltaMl > 0 && pour.kegId) {
    kegService.subtractFromKeg(pour.kegId, deltaMl);
    pour.lastReportedVolumeMl = pour.volumeMl;
  }

  const tap = kegService.getTap(tapId);
  hub.broadcast('pour_update', {
    tapId,
    pourId: pour.id,
    pulseCount: pour.pulseCount,
    volumeMl: pour.volumeMl,
    remainingMl: tap ? tap.remaining_ml : null,
    capacityMl: tap ? tap.capacity_ml : null,
  });

  // Avoid full status (incl. pour history queries) on every pulse — kiosk patches from pour_update.
  return pour;
}

function endPour(tapId) {
  clearIdleTimer(tapId);

  const pour = activePours.get(tapId);
  if (!pour) {
    return null;
  }

  updateActivePour(tapId);

  const endedAt = new Date().toISOString();
  const db = getDb();
  db.prepare(
    `
    UPDATE pours
    SET ended_at = ?, volume_ml = ?, pulse_count = ?
    WHERE id = ?
  `,
  ).run(endedAt, pour.volumeMl, pour.pulseCount, pour.id);

  activePours.delete(tapId);

  hub.broadcast('pour_end', {
    tapId,
    pourId: pour.id,
    volumeMl: pour.volumeMl,
    pulseCount: pour.pulseCount,
    endedAt,
  });

  hub.broadcast('status', kegService.getStatus());
  return pour;
}

function discardPending(tapId) {
  pendingPours.delete(tapId);
  clearIdleTimer(tapId);
}

function onIdleTimeout(tapId) {
  if (pendingPours.has(tapId)) {
    // CO2 / equilibrium blips never reached the minimum pour volume
    discardPending(tapId);
    return;
  }
  endPour(tapId);
}

function scheduleIdleEnd(tapId) {
  clearIdleTimer(tapId);
  const timer = setTimeout(onIdleTimeout, getPourIdleMs(), tapId);
  idleTimers.set(tapId, timer);
}

function handlePulse(tapId) {
  const calibration = calibrationSessions.get(tapId);
  if (calibration && calibration.active) {
    calibration.pulseCount += 1;
    hub.broadcast('calibration_pulse', {
      tapId,
      pulseCount: calibration.pulseCount,
    });
    return;
  }

  let pour = activePours.get(tapId);
  if (pour) {
    pour.pulseCount += 1;
    updateActivePour(tapId);
    scheduleIdleEnd(tapId);
    return;
  }

  let pending = pendingPours.get(tapId);
  if (!pending) {
    pending = createPendingPour(tapId);
    if (!pending) {
      return;
    }
    pendingPours.set(tapId, pending);
  }

  pending.pulseCount += 1;
  pending.volumeMl = pulsesToMl(pending.pulseCount, pending.pulsesPerLiter);

  if (pending.volumeMl < getMinPourMl()) {
    scheduleIdleEnd(tapId);
    return;
  }

  commitPour(pending);
  updateActivePour(tapId);
  scheduleIdleEnd(tapId);
}

function startCalibration(tapId) {
  calibrationSessions.set(tapId, {
    active: true,
    pulseCount: 0,
    startedAt: new Date().toISOString(),
  });

  return calibrationSessions.get(tapId);
}

function finishCalibration(tapId, knownVolumeMl) {
  const session = calibrationSessions.get(tapId);
  if (!session) {
    throw new Error('No calibration session for this tap');
  }

  const volumeMl = Number(knownVolumeMl);
  if (!Number.isFinite(volumeMl) || volumeMl <= 0) {
    throw new Error('known_volume_ml must be a positive number');
  }

  if (session.pulseCount <= 0) {
    throw new Error('No pulses recorded during calibration');
  }

  const pulsesPerLiter = session.pulseCount / (volumeMl / 1000);
  session.active = false;
  calibrationSessions.delete(tapId);

  const tap = kegService.updateTap(tapId, { pulses_per_liter: pulsesPerLiter });

  return {
    tap,
    pulseCount: session.pulseCount,
    knownVolumeMl: volumeMl,
    pulsesPerLiter,
  };
}

function cancelCalibration(tapId) {
  calibrationSessions.delete(tapId);
}

function getCalibration(tapId) {
  return calibrationSessions.get(tapId) || null;
}

function getActivePours() {
  const result = [];
  for (const pour of activePours.values()) {
    result.push({
      tapId: pour.tapId,
      pourId: pour.id,
      pulseCount: pour.pulseCount,
      volumeMl: pour.volumeMl,
      startedAt: pour.startedAt,
    });
  }
  return result;
}

module.exports = {
  handlePulse,
  endPour,
  startCalibration,
  finishCalibration,
  cancelCalibration,
  getCalibration,
  getActivePours,
  pulsesToMl,
};
