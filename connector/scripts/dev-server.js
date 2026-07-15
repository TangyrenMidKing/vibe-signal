/**
 * Dev harness: runs ConnectorServer without VS Code for local testing.
 *   node scripts/dev-server.js
 */
"use strict";

const path = require("path");
const { pathToFileURL } = require("url");

// Compile first with `npm run compile`, then require out/
const { StateMachine } = require("../out/state");
const { DecisionHub } = require("../out/decisionHub");
const { ConnectorServer } = require("../out/server");
const { generateToken, preferredLanAddress } = require("../out/network");

async function main() {
  const port = Number(process.env.PORT || 8787);
  const token = process.env.AGENTPULSE_TOKEN || generateToken();
  const state = new StateMachine();
  const decisions = new DecisionHub();
  const server = new ConnectorServer({
    port,
    token,
    state,
    decisions,
    permissionTimeoutMs: 30_000,
    stopTimeoutMs: 15_000,
    onClientCountChange: (n) => console.log("clients:", n),
  });

  await server.start();
  const host = preferredLanAddress();
  console.log("Vibe Signal dev server");
  console.log(`  health  http://127.0.0.1:${port}/health`);
  console.log(`  ws      ws://${host}:${port}/?token=${token}`);
  console.log(`  token   ${token}`);
  console.log("Simulating: working → waiting → completed in 6s...");

  setTimeout(() => state.setState("working", "Dev: coding"), 1000);
  setTimeout(() => {
    decisions.beginPermission("dev-1");
    state.setState("waiting", "Dev: approve install?");
  }, 3000);
  setTimeout(() => {
    decisions.beginStop("dev-1");
    state.setState("completed", "Dev: done");
  }, 6000);

  process.on("SIGINT", async () => {
    await server.stop();
    process.exit(0);
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
