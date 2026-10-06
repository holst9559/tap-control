const http = require('http');
const path = require('path');
const express = require('express');
const { WebSocketServer } = require('ws');
const config = require('./config');
const { openDatabase } = require('./db/client');
const { createRouter, getStatusPayload } = require('./api/routes');
const kegService = require('./services/kegService');
const pourService = require('./services/pourService');
const pulseMeter = require('./gpio/pulseMeter');
const hub = require('./ws/hub');

function onPulse(tapId) {
  pourService.handlePulse(tapId);
}

function onWsClose(ws) {
  hub.removeClient(ws);
}

function onWsConnection(ws) {
  hub.addClient(ws);
  ws.send(
    JSON.stringify({
      event: 'status',
      payload: getStatusPayload(),
    }),
  );
  ws.on('close', onWsClose.bind(null, ws));
}

function serveAdmin(_req, res) {
  res.sendFile(path.join(config.publicDir, 'admin', 'index.html'));
}

function onListen() {
  console.log(`[tap-control] listening on http://${config.host}:${config.port}`);
  console.log(`[tap-control] kiosk:  http://localhost:${config.port}/`);
  console.log(`[tap-control] CMS:    http://localhost:${config.port}/admin`);
}

function startServer() {
  openDatabase();

  const app = express();
  app.use(express.json());
  app.use(express.urlencoded({ extended: false }));

  app.use('/api', createRouter());
  app.use(express.static(config.publicDir));
  app.get('/admin', serveAdmin);

  const server = http.createServer(app);
  const wss = new WebSocketServer({ server, path: '/ws' });
  wss.on('connection', onWsConnection);

  const taps = kegService.listTaps();
  const meters = pulseMeter.startPulseMeters(taps, onPulse);
  console.log(`[tap-control] gpio mode: ${meters.pigpioAvailable ? 'pigpio' : 'mock'}`);

  server.listen(config.port, config.host, onListen);
  return server;
}

startServer();
