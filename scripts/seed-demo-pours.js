/**
 * Insert demo pour history for each tap (for kiosk UI testing).
 *
 * Usage (app can be running or stopped):
 *   node scripts/seed-demo-pours.js
 *
 * Then refresh the kiosk / wait for the next status push.
 */
const { getDb, openDatabase } = require('../src/db/client');

const POURS_PER_TAP = 8;

openDatabase();
const db = getDb();

const taps = db
  .prepare(
    `
  SELECT t.id AS tap_id, t.keg_id, t.pulses_per_liter, k.remaining_ml
  FROM taps t
  LEFT JOIN kegs k ON k.id = t.keg_id
  ORDER BY t.id
`,
  )
  .all();

if (taps.length === 0) {
  console.error('No taps found. Start the app once so defaults are seeded.');
  process.exit(1);
}

const insert = db.prepare(`
  INSERT INTO pours (tap_id, keg_id, started_at, ended_at, volume_ml, pulse_count)
  VALUES (@tap_id, @keg_id, @started_at, @ended_at, @volume_ml, @pulse_count)
`);

const volumesMl = [330, 400, 250, 500, 300, 450, 200, 380];

const seed = db.transaction(() => {
  for (const tap of taps) {
    if (!tap.keg_id) {
      console.warn(`Tap ${tap.tap_id}: no keg assigned — skipping`);
      continue;
    }

    const ppl = Number(tap.pulses_per_liter) || 1260;
    let remaining = Number(tap.remaining_ml) || 0;

    for (let i = 0; i < POURS_PER_TAP; i += 1) {
      const volumeMl = volumesMl[i % volumesMl.length];
      const minutesAgo = (POURS_PER_TAP - i) * 12 + tap.tap_id * 3;
      const ended = new Date(Date.now() - minutesAgo * 60 * 1000);
      const started = new Date(ended.getTime() - 20 * 1000);
      const pulseCount = Math.max(1, Math.round((volumeMl / 1000) * ppl));

      insert.run({
        tap_id: tap.tap_id,
        keg_id: tap.keg_id,
        started_at: started.toISOString(),
        ended_at: ended.toISOString(),
        volume_ml: volumeMl,
        pulse_count: pulseCount,
      });

      remaining = Math.max(0, remaining - volumeMl);
    }

    db.prepare('UPDATE kegs SET remaining_ml = ?, updated_at = ? WHERE id = ?').run(
      remaining,
      new Date().toISOString(),
      tap.keg_id,
    );

    console.log(`Tap ${tap.tap_id}: added ${POURS_PER_TAP} demo pours (remaining ${remaining} ml)`);
  }
});

seed();
console.log('Done. Refresh the kiosk (or wait for WS status) to see the history.');
