CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS taps (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  gpio_pin INTEGER NOT NULL UNIQUE,
  pulses_per_liter REAL NOT NULL,
  sound_file TEXT,
  keg_id INTEGER
);

CREATE TABLE IF NOT EXISTS kegs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  brewery TEXT,
  notes TEXT,
  capacity_ml REAL NOT NULL,
  remaining_ml REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'stored',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pours (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tap_id INTEGER NOT NULL,
  keg_id INTEGER,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  volume_ml REAL NOT NULL DEFAULT 0,
  pulse_count INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (tap_id) REFERENCES taps(id),
  FOREIGN KEY (keg_id) REFERENCES kegs(id)
);

CREATE INDEX IF NOT EXISTS idx_pours_started ON pours(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_kegs_status ON kegs(status);
