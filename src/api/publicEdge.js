/**
 * When traffic arrives via Cloudflare Tunnel, only the public kiosk surface is
 * allowed. /admin and mutating/debug APIs stay LAN-only (no Cf-Ray header).
 */

const PUBLIC_API_GET = new Set(['/status', '/settings']);

function isCloudflareRequest(req) {
  return Boolean(req.headers['cf-ray']);
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
  if (!isCloudflareRequest(req)) {
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
  isCloudflareRequest,
  isAdminPath,
  isAllowedPublicApi,
};
