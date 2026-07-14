/**
 * Standalone smoke test for the connector WebSocket + HTTP API.
 * Run against a live extension OR the local harness in scripts/dev-server.js
 *
 *   node scripts/ws-client.js [host] [port] [token]
 */
"use strict";

const http = require("http");
const WebSocket = require("ws");

const host = process.argv[2] || "127.0.0.1";
const port = Number(process.argv[3] || 8787);
const token = process.argv[4] || process.env.AGENTPULSE_TOKEN || "";

function get(path) {
  return new Promise((resolve, reject) => {
    http
      .get({ host, port, path }, (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          resolve({
            status: res.statusCode,
            body: Buffer.concat(chunks).toString("utf8"),
          });
        });
      })
      .on("error", reject);
  });
}

async function main() {
  console.log(`Health check http://${host}:${port}/health`);
  const health = await get("/health");
  console.log(health.status, health.body);

  if (!token) {
    console.log("No token provided — skip WS. Set AGENTPULSE_TOKEN or pass as argv[4].");
    return;
  }

  const url = `ws://${host}:${port}/?token=${encodeURIComponent(token)}`;
  console.log("Connecting", url);
  const ws = new WebSocket(url);

  ws.on("open", () => {
    console.log("WS open — sending voice_prompt");
    ws.send(
      JSON.stringify({
        type: "command",
        command: "voice_prompt",
        text: "Hello from ws-client",
      })
    );
  });

  ws.on("message", (data) => {
    console.log("<-", String(data));
  });

  ws.on("error", (err) => {
    console.error("WS error", err.message);
  });

  setTimeout(() => {
    ws.close();
    process.exit(0);
  }, 3000);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
