const { getDb } = require('../db/client');
const hub = require('../ws/hub');

function nowIso() {
  return new Date().toISOString();
}

function listTaps() {
  const db = getDb();
  return db
    .prepare(
      `
    SELECT
      t.id,
      t.name,
      t.gpio_pin,
      t.pulses_per_liter,
      t.sound_file,
      t.keg_id,
      k.name AS keg_name,
      k.brewery AS keg_brewery,
      k.notes AS keg_notes,
      k.capacity_ml,
      k.remaining_ml,
      k.status AS keg_status
    FROM taps t
    LEFT JOIN kegs k ON k.id = t.keg_id
    ORDER BY t.id ASC
  `,
    )
    .all();
}

function getTap(tapId) {
  const db = getDb();
  return db
    .prepare(
      `
    SELECT
      t.id,
      t.name,
      t.gpio_pin,
      t.pulses_per_liter,
      t.sound_file,
      t.keg_id,
      k.name AS keg_name,
      k.brewery AS keg_brewery,
      k.notes AS keg_notes,
      k.capacity_ml,
      k.remaining_ml,
      k.status AS keg_status
    FROM taps t
    LEFT JOIN kegs k ON k.id = t.keg_id
    WHERE t.id = ?
  `,
    )
    .get(tapId);
}

function listKegs() {
  const db = getDb();
  return db
    .prepare(
      `
    SELECT id, name, brewery, notes, capacity_ml, remaining_ml, status, created_at, updated_at
    FROM kegs
    ORDER BY updated_at DESC
  `,
    )
    .all();
}

function getKeg(kegId) {
  const db = getDb();
  return db
    .prepare(
      `
    SELECT id, name, brewery, notes, capacity_ml, remaining_ml, status, created_at, updated_at
    FROM kegs
    WHERE id = ?
  `,
    )
    .get(kegId);
}

function createKeg(input) {
  const db = getDb();
  const capacity = Number(input.capacity_ml);
  let remaining = input.remaining_ml != null ? Number(input.remaining_ml) : capacity;

  if (!Number.isFinite(capacity) || capacity <= 0) {
    throw new Error('capacity_ml must be a positive number');
  }

  if (!Number.isFinite(remaining) || remaining < 0) {
    throw new Error('remaining_ml must not be negative');
  }

  if (remaining > capacity) {
    remaining = capacity;
  }

  const stamp = nowIso();
  const result = db
    .prepare(
      `
    INSERT INTO kegs (name, brewery, notes, capacity_ml, remaining_ml, status, created_at, updated_at)
    VALUES (@name, @brewery, @notes, @capacity_ml, @remaining_ml, @status, @created_at, @updated_at)
  `,
    )
    .run({
      name: String(input.name || 'Namnlös').trim(),
      brewery: input.brewery ? String(input.brewery).trim() : null,
      notes: input.notes ? String(input.notes).trim() : null,
      capacity_ml: capacity,
      remaining_ml: remaining,
      status: input.status || 'stored',
      created_at: stamp,
      updated_at: stamp,
    });

  const keg = getKeg(result.lastInsertRowid);
  hub.broadcast('kegs_changed', { kegs: listKegs() });
  return keg;
}

function updateKeg(kegId, input) {
  const db = getDb();
  const existing = getKeg(kegId);
  if (!existing) {
    throw new Error('Keg not found');
  }

  const name = input.name != null ? String(input.name).trim() : existing.name;
  const brewery =
    input.brewery !== undefined
      ? input.brewery
        ? String(input.brewery).trim()
        : null
      : existing.brewery;
  const notes =
    input.notes !== undefined ? (input.notes ? String(input.notes).trim() : null) : existing.notes;

  let capacity = input.capacity_ml != null ? Number(input.capacity_ml) : existing.capacity_ml;
  let remaining = input.remaining_ml != null ? Number(input.remaining_ml) : existing.remaining_ml;
  let status = input.status != null ? String(input.status) : existing.status;

  if (!Number.isFinite(capacity) || capacity <= 0) {
    throw new Error('capacity_ml must be a positive number');
  }

  if (!Number.isFinite(remaining) || remaining < 0) {
    throw new Error('remaining_ml must not be negative');
  }

  if (remaining > capacity) {
    remaining = capacity;
  }

  if (remaining <= 0) {
    remaining = 0;
    if (status === 'on_tap') {
      status = 'empty';
    }
  }

  db.prepare(
    `
    UPDATE kegs
    SET name = @name,
        brewery = @brewery,
        notes = @notes,
        capacity_ml = @capacity_ml,
        remaining_ml = @remaining_ml,
        status = @status,
        updated_at = @updated_at
    WHERE id = @id
  `,
  ).run({
    id: kegId,
    name,
    brewery,
    notes,
    capacity_ml: capacity,
    remaining_ml: remaining,
    status,
    updated_at: nowIso(),
  });

  const keg = getKeg(kegId);
  hub.broadcast('status', getStatus());
  hub.broadcast('kegs_changed', { kegs: listKegs() });
  return keg;
}

function assignKegTx(payload) {
  const db = getDb();

  if (payload.previousKegId && payload.previousKegId !== payload.kegId) {
    db.prepare(
      `
      UPDATE kegs
      SET status = ?, updated_at = ?
      WHERE id = ?
    `,
    ).run(payload.previousStatus, payload.stamp, payload.previousKegId);
  }

  db.prepare(
    `
    UPDATE kegs
    SET status = 'on_tap', updated_at = ?
    WHERE id = ?
  `,
  ).run(payload.stamp, payload.kegId);

  db.prepare('UPDATE taps SET keg_id = ? WHERE id = ?').run(payload.kegId, payload.tapId);
}

function assignKegToTap(tapId, input) {
  const db = getDb();
  const tap = getTap(tapId);
  if (!tap) {
    throw new Error('Tap not found');
  }

  let kegId = input.keg_id != null ? Number(input.keg_id) : null;

  if (!kegId && input.create) {
    const created = createKeg({
      name: input.name,
      brewery: input.brewery,
      notes: input.notes,
      capacity_ml: input.capacity_ml,
      remaining_ml: input.remaining_ml,
      status: 'on_tap',
    });
    kegId = created.id;
  }

  if (!kegId) {
    throw new Error('keg_id or create payload is required');
  }

  const keg = getKeg(kegId);
  if (!keg) {
    throw new Error('Keg not found');
  }

  const tx = db.transaction(assignKegTx);
  tx({
    previousKegId: tap.keg_id,
    previousStatus: input.previous_status || 'stored',
    kegId,
    tapId,
    stamp: nowIso(),
  });

  const updated = getTap(tapId);
  hub.broadcast('status', getStatus());
  hub.broadcast('kegs_changed', { kegs: listKegs() });
  return updated;
}

function updateTap(tapId, input) {
  const db = getDb();
  const tap = getTap(tapId);
  if (!tap) {
    throw new Error('Tap not found');
  }

  const name = input.name != null ? String(input.name).trim() : tap.name;
  const pulses =
    input.pulses_per_liter != null ? Number(input.pulses_per_liter) : tap.pulses_per_liter;
  const soundFile = input.sound_file !== undefined ? input.sound_file || null : tap.sound_file;

  if (!Number.isFinite(pulses) || pulses <= 0) {
    throw new Error('pulses_per_liter must be a positive number');
  }

  db.prepare(
    `
    UPDATE taps
    SET name = @name,
        pulses_per_liter = @pulses_per_liter,
        sound_file = @sound_file
    WHERE id = @id
  `,
  ).run({
    id: tapId,
    name,
    pulses_per_liter: pulses,
    sound_file: soundFile,
  });

  const updated = getTap(tapId);
  hub.broadcast('status', getStatus());
  return updated;
}

function subtractFromKeg(kegId, volumeMl) {
  const db = getDb();
  const keg = getKeg(kegId);
  if (!keg) {
    return null;
  }

  let remaining = Math.max(0, keg.remaining_ml - volumeMl);
  let status = keg.status;
  if (remaining <= 0) {
    remaining = 0;
    status = 'empty';
  }

  db.prepare(
    `
    UPDATE kegs
    SET remaining_ml = ?, status = ?, updated_at = ?
    WHERE id = ?
  `,
  ).run(remaining, status, nowIso(), kegId);

  return getKeg(kegId);
}

function listPours(limit) {
  const db = getDb();
  const max = Number(limit) || 50;
  return db
    .prepare(
      `
    SELECT
      p.id,
      p.tap_id,
      p.keg_id,
      p.started_at,
      p.ended_at,
      p.volume_ml,
      p.pulse_count,
      t.name AS tap_name,
      k.name AS keg_name
    FROM pours p
    LEFT JOIN taps t ON t.id = p.tap_id
    LEFT JOIN kegs k ON k.id = p.keg_id
    ORDER BY p.started_at DESC
    LIMIT ?
  `,
    )
    .all(max);
}

function listRecentPoursForTap(tapId, limit) {
  const db = getDb();
  const max = Number(limit) || 8;
  return db
    .prepare(
      `
    SELECT
      id,
      tap_id,
      started_at,
      ended_at,
      volume_ml
    FROM pours
    WHERE tap_id = ?
    ORDER BY started_at DESC
    LIMIT ?
  `,
    )
    .all(tapId, max);
}

function attachRecentPours(taps) {
  const result = [];
  for (const tap of taps) {
    result.push({
      ...tap,
      recent_pours: listRecentPoursForTap(tap.id, 8),
    });
  }
  return result;
}

function getStatus() {
  return {
    taps: attachRecentPours(listTaps()),
  };
}

module.exports = {
  listTaps,
  getTap,
  listKegs,
  getKeg,
  createKeg,
  updateKeg,
  assignKegToTap,
  updateTap,
  subtractFromKeg,
  listPours,
  getStatus,
};
