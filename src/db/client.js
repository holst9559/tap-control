const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const Database = require('better-sqlite3');
const config = require('../config');

let db = null;

function hashPin(pin) {
  return crypto.createHash('sha256').update(String(pin)).digest('hex');
}

function ensureDirectories() {
  const dataDir = path.dirname(config.dbPath);
  fs.mkdirSync(dataDir, { recursive: true });
  fs.mkdirSync(config.soundsDir, { recursive: true });
  fs.mkdirSync(config.uploadsSoundsDir, { recursive: true });
}

function getSetting(key) {
  const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(key);
  if (!row) {
    return null;
  }
  return row.value;
}

function setSetting(key, value) {
  db.prepare(
    `
    INSERT INTO settings (key, value) VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
  `,
  ).run(key, String(value));
}

function seedDefaults() {
  if (!getSetting('cms_pin_hash')) {
    setSetting('cms_pin_hash', hashPin(config.defaultCmsPin));
  }

  if (!getSetting('pour_idle_ms')) {
    setSetting('pour_idle_ms', String(config.defaultPourIdleMs));
  }

  if (!getSetting('default_sound_file')) {
    setSetting('default_sound_file', 'default.wav');
  }

  if (!getSetting('display_units')) {
    setSetting('display_units', 'liters');
  }

  const tapCount = db.prepare('SELECT COUNT(*) AS count FROM taps').get().count;
  if (tapCount > 0) {
    return;
  }

  const insertTap = db.prepare(`
    INSERT INTO taps (id, name, gpio_pin, pulses_per_liter, sound_file, keg_id)
    VALUES (@id, @name, @gpio_pin, @pulses_per_liter, @sound_file, @keg_id)
  `);

  const now = new Date().toISOString();
  const insertKeg = db.prepare(`
    INSERT INTO kegs (name, brewery, notes, capacity_ml, remaining_ml, status, created_at, updated_at)
    VALUES (@name, @brewery, @notes, @capacity_ml, @remaining_ml, @status, @created_at, @updated_at)
  `);

  const assignKeg = db.prepare('UPDATE taps SET keg_id = ? WHERE id = ?');

  for (const tap of config.defaultTaps) {
    insertTap.run({
      id: tap.id,
      name: tap.name,
      gpio_pin: tap.gpioPin,
      pulses_per_liter: config.defaultPulsesPerLiter,
      sound_file: null,
      keg_id: null,
    });

    const result = insertKeg.run({
      name: `Beer ${tap.id}`,
      brewery: null,
      notes: null,
      capacity_ml: config.defaultKegCapacityMl,
      remaining_ml: config.defaultKegCapacityMl,
      status: 'on_tap',
      created_at: now,
      updated_at: now,
    });

    assignKeg.run(result.lastInsertRowid, tap.id);
  }
}

function openDatabase() {
  if (db) {
    return db;
  }

  ensureDirectories();
  db = new Database(config.dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  const schemaPath = path.join(__dirname, 'schema.sql');
  const schema = fs.readFileSync(schemaPath, 'utf8');
  db.exec(schema);
  seedDefaults();

  return db;
}

function getDb() {
  if (!db) {
    return openDatabase();
  }
  return db;
}

module.exports = {
  openDatabase,
  getDb,
  getSetting,
  setSetting,
  hashPin,
};
