// Online relay for Garden City Stories (same protocol as scripts/net.gd's
// Wi-Fi host). Each connection says hello, gets an id, and every message it
// sends is stamped with that id and forwarded to everyone else.
//   PORT=8910 node server.js
// Also answers plain HTTP on / with a status line (health checks, waking a
// sleeping free host).
"use strict";
const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.PORT || 8910);
const PROTOCOL = 1;
const MAX_PLAYERS = Number(process.env.MAX_PLAYERS || 16);
const MAX_MESSAGE = 16 * 1024;

const players = new Map(); // id -> socket (after hello)
let nextId = 2; // 1 is the Wi-Fi host's own id in the game; keep the numbering alike

const server = http.createServer((req, res) => {
  res.writeHead(200, { "content-type": "text/plain" });
  res.end(`Garden City Stories relay: ${players.size} player(s) online\n`);
});

const wss = new WebSocketServer({ server, maxPayload: MAX_MESSAGE });

function broadcast(text, skipId) {
  for (const [id, ws] of players) {
    if (id !== skipId && ws.readyState === ws.OPEN) ws.send(text);
  }
}

wss.on("connection", (ws) => {
  let id = 0;
  ws.isAlive = true;
  ws.on("pong", () => { ws.isAlive = true; });
  ws.on("message", (raw, isBinary) => {
    if (isBinary) return;
    let data;
    try { data = JSON.parse(raw.toString()); } catch { return; }
    if (!data || typeof data !== "object" || Array.isArray(data)) return;
    if (data.t === "hello") {
      if (id) return;
      if (players.size >= MAX_PLAYERS) { ws.close(1013, "server full"); return; }
      id = nextId++;
      players.set(id, ws);
      ws.send(JSON.stringify({ t: "welcome", id, v: PROTOCOL }));
      console.log(`player ${id} joined (${String(data.n || "").slice(0, 16)}), ${players.size} online`);
      return;
    }
    if (!id) return;
    data.id = id;
    broadcast(JSON.stringify(data), id);
  });
  ws.on("close", () => {
    if (!id) return;
    players.delete(id);
    broadcast(JSON.stringify({ t: "leave", id }), id);
    console.log(`player ${id} left, ${players.size} online`);
  });
  ws.on("error", () => {});
});

// Drop connections that stopped answering (phone lost signal)
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 15000);
wss.on("close", () => clearInterval(heartbeat));

server.listen(PORT, () => console.log(`relay listening on ${PORT}`));
