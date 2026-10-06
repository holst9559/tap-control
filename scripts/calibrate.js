/**
 * Calibration is done in the LAN CMS:
 *   http://<pi-ip>:3000/admin
 *   → Tap settings & calibration
 *   → Start calibration → pour a known volume → enter ml → Finish & save factor
 *
 * Datasheet starting point for GREDIA GR-301P2: ~1260 pulses/L
 * Always calibrate per tap after plumbing.
 */

console.log('Use the CMS calibration panel at /admin (Tap settings & calibration).');
console.log('Default pulses/L before calibration: 1260');
