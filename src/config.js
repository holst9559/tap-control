const path = require('path');

const ROOT_DIR = path.join(__dirname, '..');

const config = {
  port: Number(process.env.PORT) || 3000,
  host: process.env.HOST || '0.0.0.0',

  // Set TAP_CONTROL_MOCK=1 (or run off a Pi) to simulate pulses without pigpio
  mockGpio: process.env.TAP_CONTROL_MOCK === '1' || process.env.TAP_CONTROL_MOCK === 'true',

  dbPath: process.env.TAP_CONTROL_DB || path.join(ROOT_DIR, 'data', 'tap_control.db'),
  soundsDir: path.join(ROOT_DIR, 'sounds'),
  uploadsSoundsDir: path.join(ROOT_DIR, 'uploads', 'sounds'),
  publicDir: path.join(ROOT_DIR, 'public'),

  // GREDIA GR-301P2: F = 21 * Q (L/min) => ~1260 pulses per liter
  defaultPulsesPerLiter: 1260,

  // End a pour after this many ms with no pulses
  defaultPourIdleMs: 2500,

  // Default CMS PIN (change via CMS / settings after first login)
  defaultCmsPin: '1234',

  // BCM pin numbers for taps 1–3 (edit to match your wiring)
  defaultTaps: [
    { id: 1, name: 'Kran 1', gpioPin: 17 },
    { id: 2, name: 'Kran 2', gpioPin: 27 },
    { id: 3, name: 'Kran 3', gpioPin: 22 },
  ],

  defaultKegCapacityMl: 18927, // ~5 gal US
};

module.exports = config;
