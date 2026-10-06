const express = require('express');
const multer = require('multer');
const config = require('../config');
const auth = require('./auth');
const kegService = require('../services/kegService');
const pourService = require('../services/pourService');
const soundService = require('../services/soundService');
const { getSetting, setSetting } = require('../db/client');
const pulseMeter = require('../gpio/pulseMeter');
const hub = require('../ws/hub');

const ALLOWED_UI_THEMES = new Set([
  'amber',
  'slate',
  'forest',
  'falu',
  'midsommar',
  'lucia',
  'jul',
  'valborg',
  'kraftskiva',
  'vinter',
]);

function getSettingsPayload() {
  const theme = getSetting('ui_theme');
  return {
    pour_idle_ms: Number(getSetting('pour_idle_ms')),
    default_sound_file: getSetting('default_sound_file'),
    display_units: getSetting('display_units'),
    ui_theme: ALLOWED_UI_THEMES.has(theme) ? theme : 'amber',
  };
}

function sendError(res, err, status) {
  const code = status || 400;
  res.status(code).json({ error: err.message || String(err) });
}

function getStatusPayload() {
  return {
    ...kegService.getStatus(),
    activePours: pourService.getActivePours(),
  };
}

function createSoundStorage() {
  return multer.diskStorage({
    destination: config.uploadsSoundsDir,
    filename: soundFilename,
  });
}

function soundFilename(_req, file, cb) {
  const safe = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
  cb(null, `${Date.now()}_${safe}`);
}

function createRouter() {
  const router = express.Router();
  const upload = multer({ storage: createSoundStorage() });

  router.get('/status', onGetStatus);
  router.get('/taps', onGetTaps);
  router.get('/kegs', onGetKegs);
  router.get('/pours', onGetPours);
  router.get('/sounds', onGetSounds);
  router.get('/settings', onGetSettingsPublic);

  router.post('/auth/login', onLogin);
  router.post('/auth/logout', auth.requireAuth, onLogout);

  router.post('/kegs', auth.requireAuth, onCreateKeg);
  router.patch('/kegs/:id', auth.requireAuth, onUpdateKeg);
  router.post('/taps/:id/assign-keg', auth.requireAuth, onAssignKeg);
  router.patch('/taps/:id', auth.requireAuth, onUpdateTap);

  router.put('/settings', auth.requireAuth, onPutSettings);
  router.post('/auth/pin', auth.requireAuth, onChangePin);

  router.post('/sounds', auth.requireAuth, upload.single('file'), onUploadSound);
  router.post('/sounds/test', auth.requireAuth, onTestSound);

  router.post('/taps/:id/calibration/start', auth.requireAuth, onCalibrationStart);
  router.post('/taps/:id/calibration/finish', auth.requireAuth, onCalibrationFinish);
  router.post('/taps/:id/calibration/cancel', auth.requireAuth, onCalibrationCancel);
  router.get('/taps/:id/calibration', auth.requireAuth, onCalibrationGet);

  // Dev / bench helper — inject a pulse without hardware
  router.post('/debug/pulse/:tapId', onDebugPulse);

  return router;
}

function onGetStatus(_req, res) {
  res.json(getStatusPayload());
}

function onGetTaps(_req, res) {
  res.json({ taps: kegService.listTaps() });
}

function onGetKegs(_req, res) {
  res.json({ kegs: kegService.listKegs() });
}

function onGetPours(req, res) {
  res.json({ pours: kegService.listPours(req.query.limit) });
}

function onGetSounds(_req, res) {
  res.json({ sounds: soundService.listAvailableSounds() });
}

function onGetSettingsPublic(_req, res) {
  res.json(getSettingsPayload());
}

function onLogin(req, res) {
  const token = auth.login(req.body && req.body.pin);
  if (!token) {
    res.status(401).json({ error: 'Ogiltig PIN' });
    return;
  }
  res.json({ token });
}

function onLogout(req, res) {
  auth.logout(req.cmsToken);
  res.json({ ok: true });
}

function onCreateKeg(req, res) {
  try {
    const keg = kegService.createKeg(req.body || {});
    res.status(201).json({ keg });
  } catch (err) {
    sendError(res, err);
  }
}

function onUpdateKeg(req, res) {
  try {
    const keg = kegService.updateKeg(Number(req.params.id), req.body || {});
    res.json({ keg });
  } catch (err) {
    sendError(res, err);
  }
}

function onAssignKeg(req, res) {
  try {
    const tap = kegService.assignKegToTap(Number(req.params.id), req.body || {});
    res.json({ tap });
  } catch (err) {
    sendError(res, err);
  }
}

function onUpdateTap(req, res) {
  try {
    const tap = kegService.updateTap(Number(req.params.id), req.body || {});
    res.json({ tap });
  } catch (err) {
    sendError(res, err);
  }
}

function onPutSettings(req, res) {
  const body = req.body || {};

  if (body.pour_idle_ms != null) {
    const idle = Number(body.pour_idle_ms);
    if (!Number.isFinite(idle) || idle < 500) {
      sendError(res, new Error('pour_idle_ms måste vara >= 500'));
      return;
    }
    setSetting('pour_idle_ms', String(idle));
  }

  if (body.default_sound_file !== undefined) {
    setSetting('default_sound_file', body.default_sound_file || '');
  }

  if (body.display_units != null) {
    setSetting('display_units', String(body.display_units));
  }

  if (body.ui_theme != null) {
    const theme = String(body.ui_theme);
    if (!ALLOWED_UI_THEMES.has(theme)) {
      sendError(res, new Error('Okänt ui_theme'));
      return;
    }
    setSetting('ui_theme', theme);
  }

  const settings = getSettingsPayload();
  hub.broadcast('settings', settings);
  res.json(settings);
}

function onChangePin(req, res) {
  try {
    auth.changePin(req.body.current_pin, req.body.new_pin);
    res.json({ ok: true });
  } catch (err) {
    sendError(res, err);
  }
}

function onUploadSound(req, res) {
  if (!req.file) {
    sendError(res, new Error('Fil krävs'));
    return;
  }

  const key = `uploads/${req.file.filename}`;
  res.status(201).json({
    sound: key,
    sounds: soundService.listAvailableSounds(),
  });
}

function onTestSound(req, res) {
  const file = req.body && req.body.sound_file;
  const resolved = soundService.resolveSoundPath(file);
  if (!resolved) {
    sendError(res, new Error('Ljudfilen hittades inte'));
    return;
  }
  soundService.playFile(resolved);
  res.json({ ok: true });
}

function onCalibrationStart(req, res) {
  const tapId = Number(req.params.id);
  const session = pourService.startCalibration(tapId);
  res.json({ calibration: session });
}

function onCalibrationFinish(req, res) {
  try {
    const result = pourService.finishCalibration(
      Number(req.params.id),
      req.body && req.body.known_volume_ml,
    );
    res.json(result);
  } catch (err) {
    sendError(res, err);
  }
}

function onCalibrationCancel(req, res) {
  pourService.cancelCalibration(Number(req.params.id));
  res.json({ ok: true });
}

function onCalibrationGet(req, res) {
  res.json({ calibration: pourService.getCalibration(Number(req.params.id)) });
}

function onDebugPulse(req, res) {
  const tapId = Number(req.params.tapId);
  const count = Number(req.body && req.body.count) || 1;

  for (let i = 0; i < count; i += 1) {
    pulseMeter.injectPulse(tapId);
  }

  res.json({ ok: true, tapId, count });
}

module.exports = {
  createRouter,
  getStatusPayload,
};
