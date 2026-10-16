/**
 * When traffic arrives via the public ngrok URL, only the kiosk surface is
 * allowed. /admin and mutating/debug APIs stay LAN-only.
 *
 * Detection:
 * 1. Host / X-Forwarded-Host looks like ngrok, or matches TAP_CONTROL_PUBLIC_HOSTS
 * 2. Local reverse proxy (loopback peer) with a non-private X-Forwarded-For client
 *    — covers ngrok rewriting Host to 127.0.0.1
 */

const PUBLIC_API_GET = new Set(['/status', '/settings']);

const NGROK_HOST_RE = /(?:^|\.)ngrok(?:-free)?\.(?:app|io|dev)$/i;

function parsePublicHosts() {
  const raw = process.env.TAP_CONTROL_PUBLIC_HOSTS || '';
  if (!raw.trim()) {
    return new Set();
  }
  return new Set(
    raw
      .split(',')
      .map((h) => h.trim().toLowerCase())
      .filter(Boolean),
  );
}

function normalizeIp(ip) {
  if (!ip || typeof ip !== 'string') {
    return '';
  }
  return ip.trim().replace(/^::ffff:/i, '');
}

function isPrivateIp(ip) {
  const addr = normalizeIp(ip);
  if (!addr) {
    return false;
  }
  if (addr === '127.0.0.1' || addr === '::1' || addr === 'localhost') {
    return true;
  }
  if (addr.startsWith('10.')) {
    return true;
  }
  if (addr.startsWith('192.168.')) {
    return true;
  }
  if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(addr)) {
    return true;
  }
  // Link-local / unique-local IPv6
  if (addr.toLowerCase().startsWith('fe80:') || addr.toLowerCase().startsWith('fc') || addr.toLowerCase().startsWith('fd')) {
    return true;
  }
  return false;
}

function requestHost(req) {
  const forwarded = req.headers['x-forwarded-host'];
  if (typeof forwarded === 'string' && forwarded.trim()) {
    return forwarded.split(',')[0].trim().toLowerCase();
  }
  const host = req.headers.host;
  if (typeof host === 'string' && host.trim()) {
    return host.split(':')[0].trim().toLowerCase();
  }
  return '';
}

function clientIpFromForwarded(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded !== 'string' || !forwarded.trim()) {
    return '';
  }
  return normalizeIp(forwarded.split(',')[0]);
}

function isNgrokHost(hostname) {
  if (!hostname) {
    return false;
  }
  return NGROK_HOST_RE.test(hostname);
}

function isLocalProxyPeer(req) {
  const remote = normalizeIp(req.socket && req.socket.remoteAddress);
  return remote === '127.0.0.1' || remote === '::1';
}

function isPublicEdgeRequest(req) {
  const host = requestHost(req);
  if (host && (isNgrokHost(host) || parsePublicHosts().has(host))) {
    return true;
  }

  // ngrok may rewrite Host to the upstream (127.0.0.1). Treat loopback peers
  // that carry a public X-Forwarded-For client as the public edge.
  if (isLocalProxyPeer(req)) {
    const clientIp = clientIpFromForwarded(req);
    if (clientIp && !isPrivateIp(clientIp)) {
      return true;
    }
  }

  return false;
}

function isAdminPath(pathname) {
  return pathname === '/admin' || pathname.startsWith('/admin/');
}

function isAllowedPublicApi(req) {
  if (req.method !== 'GET') {
    return false;
  }

  const apiPath = req.path.startsWith('/api') ? req.path.slice('/api'.length) : req.path;
  return PUBLIC_API_GET.has(apiPath);
}

function sendNotFound(req, res) {
  if (req.path === '/api' || req.path.startsWith('/api/')) {
    res.status(404).json({ error: 'Not found' });
    return;
  }
  res.status(404).type('text/plain').send('Not found');
}

/** Reject anything that is not a direct LAN / loopback client. */
function requireLanOnly(req, res, next) {
  if (isPublicEdgeRequest(req)) {
    sendNotFound(req, res);
    return;
  }

  const clientIp = clientIpFromForwarded(req);
  if (clientIp && !isPrivateIp(clientIp)) {
    sendNotFound(req, res);
    return;
  }

  const remote = normalizeIp(req.socket && req.socket.remoteAddress);
  if (!isPrivateIp(remote)) {
    sendNotFound(req, res);
    return;
  }

  next();
}

function publicEdgeGuard(req, res, next) {
  if (!isPublicEdgeRequest(req)) {
    next();
    return;
  }

  if (isAdminPath(req.path)) {
    sendNotFound(req, res);
    return;
  }

  if (req.path === '/api' || req.path.startsWith('/api/')) {
    if (isAllowedPublicApi(req)) {
      next();
      return;
    }
    sendNotFound(req, res);
    return;
  }

  next();
}

module.exports = {
  publicEdgeGuard,
  requireLanOnly,
  isPublicEdgeRequest,
  isPrivateIp,
  isAdminPath,
  isAllowedPublicApi,
};
