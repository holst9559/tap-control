/**
 * When traffic arrives via the public ngrok URL, only the kiosk surface is
 * allowed. /admin and mutating/debug APIs stay LAN-only.
 *
 * Detection: Host / X-Forwarded-Host looks like an ngrok hostname, or matches
 * TAP_CONTROL_PUBLIC_HOSTS (comma-separated), for reserved custom domains.
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

function isNgrokHost(hostname) {
  if (!hostname) {
    return false;
  }
  return NGROK_HOST_RE.test(hostname);
}

function isPublicEdgeRequest(req) {
  const host = requestHost(req);
  if (!host) {
    return false;
  }
  if (isNgrokHost(host)) {
    return true;
  }
  return parsePublicHosts().has(host);
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

function publicEdgeGuard(req, res, next) {
  if (!isPublicEdgeRequest(req)) {
    next();
    return;
  }

  if (isAdminPath(req.path)) {
    res.status(404).type('text/plain').send('Not found');
    return;
  }

  if (req.path === '/api' || req.path.startsWith('/api/')) {
    if (isAllowedPublicApi(req)) {
      next();
      return;
    }
    res.status(404).json({ error: 'Not found' });
    return;
  }

  next();
}

module.exports = {
  publicEdgeGuard,
  isPublicEdgeRequest,
  isAdminPath,
  isAllowedPublicApi,
};
