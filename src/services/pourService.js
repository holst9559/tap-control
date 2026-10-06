const { getDb, getSetting } = require('../db/client');
const kegService = require('./kegService');
const soundService = require('./soundService');
const hub = require('../ws/hub');

const activePours = new Map();
const idleTimers = new Map();
const calibrationSessions = new Map();

function getPourIdleMs() {
  const raw = getSetting('pour_idle_ms');
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 500) {
    return 2500;
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

function openPour(tapId) {
  const db = getDb();
  const tap = kegService.getTap(tapId);
  if (!tap) {
    return null;
  }

  const startedAt = new Date().toISOString();
  const result = db
    .prepare(
      `
    INSERT INTO pours (tap_id, keg_id, started_at, ended_at, volume_ml, pulse_count)
    VALUES (?, ?, ?, NULL, 0, 0)
  `,
    )
    .run(tapId, tap.keg_id, startedAt);

  const pour = {
    id: result.lastInsertRowid,
    tapId,
    kegId: tap.keg_id,
    startedAt,
    pulseCount: 0,
    volumeMl: 0,
    pulsesPerLiter: tap.pulses_per_liter,
    lastReportedVolumeMl: 0,
  };

  activePours.set(tapId, pour);
  soundService.playPourSound(tapId);

  hub.broadcast('pour_start', {
    tapId,
    pourId: pour.id,
    kegId: pour.kegId,
    startedAt,
  });

  hub.broadcast('status', kegService.getStatus());
  return pour;
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

function onIdleTimeout(tapId) {
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
  if (!pour) {
    pour = openPour(tapId);
    if (!pour) {
      return;
    }
  }

  pour.pulseCount += 1;
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
    throw new Error('Ingen kalibreringssession för den här kranen');
  }

  const volumeMl = Number(knownVolumeMl);
  if (!Number.isFinite(volumeMl) || volumeMl <= 0) {
    throw new Error('known_volume_ml måste vara ett positivt tal');
  }

  if (session.pulseCount <= 0) {
    throw new Error('Inga pulser registrerade under kalibreringen');
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
