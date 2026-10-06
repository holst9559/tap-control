const clients = new Set();

function addClient(ws) {
  clients.add(ws);
}

function removeClient(ws) {
  clients.delete(ws);
}

function broadcast(event, payload) {
  const message = JSON.stringify({ event, payload });

  for (const ws of clients) {
    if (ws.readyState === 1) {
      ws.send(message);
    }
  }
}

function clientCount() {
  return clients.size;
}

module.exports = {
  addClient,
  removeClient,
  broadcast,
  clientCount,
};
