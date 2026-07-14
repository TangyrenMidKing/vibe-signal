#!/usr/bin/env node
/**
 * AgentPulse Codex lifecycle hook.
 * Reads event JSON from stdin, POSTs to the local connector, and for
 * PermissionRequest / Stop long-polls for a phone/watch decision.
 *
 * Usage: node hook.js --port 8787
 * Marker: agentpulse-hook (for installer filtering)
 */
"use strict";

const http = require("http");

const AGENTPULSE_MARKER = "agentpulse-hook"; // eslint-disable-line no-unused-vars

function parseArgs(argv) {
  let port = 8787;
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--port" && argv[i + 1]) {
      port = Number(argv[++i]);
    }
  }
  // Fall back to ~/.agentpulse/port if present
  try {
    const fs = require("fs");
    const os = require("os");
    const path = require("path");
    const p = path.join(os.homedir(), ".agentpulse", "port");
    if (fs.existsSync(p)) {
      const n = Number(fs.readFileSync(p, "utf8").trim());
      if (!Number.isNaN(n) && n > 0) port = n;
    }
  } catch {
    // ignore
  }
  return { port };
}

function readStdin() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    process.stdin.on("data", (c) => chunks.push(c));
    process.stdin.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8").trim();
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(err);
      }
    });
    process.stdin.on("error", reject);
  });
}

function request(port, method, path, body, timeoutMs) {
  return new Promise((resolve, reject) => {
    const payload = body ? Buffer.from(JSON.stringify(body), "utf8") : null;
    const req = http.request(
      {
        host: "127.0.0.1",
        port,
        path,
        method,
        timeout: timeoutMs,
        headers: payload
          ? {
              "Content-Type": "application/json",
              "Content-Length": payload.length,
            }
          : {},
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let json = {};
          try {
            json = text ? JSON.parse(text) : {};
          } catch {
            json = { raw: text };
          }
          resolve({ status: res.statusCode || 0, json });
        });
      }
    );
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("timeout"));
    });
    if (payload) req.write(payload);
    req.end();
  });
}

function writeStdout(obj) {
  process.stdout.write(JSON.stringify(obj));
}

async function main() {
  const { port } = parseArgs(process.argv);
  let event;
  try {
    event = await readStdin();
  } catch {
    process.exit(0);
  }

  const hookEvent = String(event.hook_event_name || "");
  const turnId = String(event.turn_id || event.session_id || "default");

  try {
    await request(port, "POST", "/hook/event", event, 5_000);
  } catch {
    // Connector not running — no-op so Codex continues
    process.exit(0);
  }

  if (hookEvent === "PermissionRequest") {
    try {
      const { json } = await request(
        port,
        "GET",
        `/decision/permission?turn_id=${encodeURIComponent(turnId)}&timeout_ms=120000`,
        null,
        125_000
      );
      if (json.decision === "allow") {
        writeStdout({
          hookSpecificOutput: {
            hookEventName: "PermissionRequest",
            decision: { behavior: "allow" },
          },
        });
      } else if (json.decision === "deny") {
        writeStdout({
          hookSpecificOutput: {
            hookEventName: "PermissionRequest",
            decision: {
              behavior: "deny",
              message: json.message || "Denied from AgentPulse",
            },
          },
        });
      }
      // timeout → silent exit
    } catch {
      // silent
    }
    process.exit(0);
  }

  if (hookEvent === "Stop") {
    try {
      const { json } = await request(
        port,
        "GET",
        `/decision/stop?turn_id=${encodeURIComponent(turnId)}&timeout_ms=60000`,
        null,
        65_000
      );
      if (json.decision === "continue" && json.reason) {
        writeStdout({
          decision: "block",
          reason: String(json.reason),
        });
      }
    } catch {
      // silent
    }
    process.exit(0);
  }

  // Other events: already POSTed; exit cleanly (Stop hooks require JSON, others OK empty)
  if (hookEvent === "Stop" || hookEvent === "SubagentStop") {
    writeStdout({});
  }
  process.exit(0);
}

main().catch(() => process.exit(0));
