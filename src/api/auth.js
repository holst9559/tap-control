const crypto = require('crypto');
const { getSetting, setSetting, hashPin } = require('../db/client');

const sessions = new Map();
const SESSION_TTL_MS = 12 * 60 * 60 * 1000;

function createToken() {
  return crypto.randomBytes(24).toString('hex');
}

function pruneSessions() {
  const now = Date.now();
  for (const [token, session] of sessions.entries()) {
    if (session.expiresAt <= now) {
      sessions.delete(token);
    }
  }
}

function login(pin) {
  pruneSessions();
  const expected = getSetting('cms_pin_hash');
  const actual = hashPin(pin);

  if (!expected || actual !== expected) {
    return null;
  }

  const token = createToken();
  sessions.set(token, {
    expiresAt: Date.now() + SESSION_TTL_MS,
  });

  return token;
}

function logout(token) {
  if (token) {
    sessions.delete(token);
  }
}

function isValidToken(token) {
  if (!token) {
    return false;
  }

  pruneSessions();
  const session = sessions.get(token);
  if (!session) {
    return false;
  }

  if (session.expiresAt <= Date.now()) {
    sessions.delete(token);
    return false;
  }

  session.expiresAt = Date.now() + SESSION_TTL_MS;
  return true;
}

function getTokenFromRequest(req) {
  const header = req.headers['x-cms-token'];
  if (header) {
    return String(header);
  }

  if (req.headers.authorization && req.headers.authorization.startsWith('Bearer ')) {
    return req.headers.authorization.slice(7);
  }

  if (req.query && req.query.token) {
    return String(req.query.token);
  }

  return null;
}

function requireAuth(req, res, next) {
  const token = getTokenFromRequest(req);
  if (!isValidToken(token)) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  req.cmsToken = token;
  next();
}

function changePin(currentPin, newPin) {
  const expected = getSetting('cms_pin_hash');
  if (hashPin(currentPin) !== expected) {
    throw new Error('Current PIN is incorrect');
  }

  if (!newPin || String(newPin).length < 4) {
    throw new Error('New PIN must be at least 4 characters');
  }

  setSetting('cms_pin_hash', hashPin(newPin));
}

module.exports = {
  login,
  logout,
  isValidToken,
  getTokenFromRequest,
  requireAuth,
  changePin,
  hashPin,
};
