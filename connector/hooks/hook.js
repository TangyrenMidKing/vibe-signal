#!/usr/bin/env node
/**
 * Vibe Signal Codex lifecycle hook.
 * Reads event JSON from stdin, POSTs to the local connector, and for
 * PermissionRequest / Stop long-polls for a phone/watch decision.
 *
 * Usage: node hook.js --port 8787
 * Logs: ~/.agentpulse/hook.log
 */
"use strict";

const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");

const LOG_DIR = path.join(os.homedir(), ".agentpulse");
const LOG_FILE = path.join(LOG_DIR, "hook.log");

function log(line) {
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    const stamp = new Date().toISOString();
    fs.appendFileSync(LOG_FILE, `[${stamp}] ${line}\n`, "utf8");
  } catch {
    // ignore
  }
}

function parseArgs(argv) {
  let port = 8787;
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--port" && argv[i + 1]) {
      port = Number(argv[++i]);
    }
  }
  try {
    const p = path.join(LOG_DIR, "port");
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

function request(port, method, reqPath, body, timeoutMs) {
  return new Promise((resolve, reject) => {
    const payload = body ? Buffer.from(JSON.stringify(body), "utf8") : null;
    const req = http.request(
      {
        host: "127.0.0.1",
        port,
        path: reqPath,
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
  log(`start port=${port} argv=${JSON.stringify(process.argv)}`);

  let event;
  try {
    event = await readStdin();
  } catch (err) {
    log(`stdin parse error: ${err && err.message ? err.message : err}`);
    process.exit(0);
  }

  const hookEvent = String(
    event.hook_event_name || event.hookEventName || event.type || ""
  );
  const turnId = String(event.turn_id || event.session_id || "default");
  log(`event=${hookEvent || "(empty)"} keys=${Object.keys(event).join(",")}`);

  try {
    const res = await request(port, "POST", "/hook/event", event, 5_000);
    log(`POST /hook/event -> ${res.status} ${JSON.stringify(res.json)}`);
  } catch (err) {
    log(`POST failed: ${err && err.message ? err.message : err}`);
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
      log(`permission decision=${JSON.stringify(json)}`);
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
              message: json.message || "Denied from Vibe Signal",
            },
          },
        });
      }
    } catch (err) {
      log(`permission wait failed: ${err && err.message ? err.message : err}`);
    }
    process.exit(0);
  }

  if (hookEvent === "Stop") {
    try {
      const { json } = await request(
        port,
        "GET",
        `/decision/stop?turn_id=${encodeURIComponent(turnId)}&timeout_ms=300000`,
        null,
        305_000
      );
      log(`stop decision=${JSON.stringify(json)}`);
      if (json.decision === "continue" && json.reason) {
        writeStdout({
          decision: "block",
          reason: String(json.reason),
        });
      }
    } catch (err) {
      log(`stop wait failed: ${err && err.message ? err.message : err}`);
    }
    process.exit(0);
  }

  process.exit(0);
}

main().catch((err) => {
  log(`fatal: ${err && err.message ? err.message : err}`);
  process.exit(0);
});
