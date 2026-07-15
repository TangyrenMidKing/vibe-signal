"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const userDir = path.join(os.homedir(), ".agentpulse");
fs.mkdirSync(userDir, { recursive: true });
const hookSrc = path.join(__dirname, "..", "hooks", "hook.js");
const hookDest = path.join(userDir, "hook.js");
fs.copyFileSync(hookSrc, hookDest);
fs.writeFileSync(path.join(userDir, "port"), "8787");

let nodeWin = "node";
try {
  const out = execFileSync("where.exe", ["node"], { encoding: "utf8" })
    .split(/\r?\n/)
    .map((s) => s.trim())
    .find((s) => s.toLowerCase().endsWith("node.exe"));
  if (out) nodeWin = out;
} catch {
  const guess = path.join(
    process.env.ProgramFiles || "C:\\Program Files",
    "nodejs",
    "node.exe"
  );
  if (fs.existsSync(guess)) nodeWin = guess;
}

const winCmd = path.join(userDir, "run-hook.cmd");
fs.writeFileSync(
  winCmd,
  ["@echo off", `"${nodeWin}" "%~dp0hook.js" --port 8787`, ""].join("\r\n"),
  "utf8"
);

const cmdUnix = `node "${hookDest.replace(/\\/g, "/")}" --port 8787`;

function handler(status) {
  return {
    type: "command",
    command: cmdUnix,
    commandWindows: winCmd,
    timeout: 180,
    statusMessage: `Vibe Signal ${status}`,
  };
}

const hooks = {
  SessionStart: [{ hooks: [handler("session")] }],
  UserPromptSubmit: [{ hooks: [handler("prompt")] }],
  PreToolUse: [{ hooks: [handler("tool")] }],
  PostToolUse: [{ hooks: [handler("tool result")] }],
  PermissionRequest: [{ hooks: [handler("approval")] }],
  Stop: [{ hooks: [handler("stop")] }],
};

const out = {
  description:
    "Includes Vibe Signal companion hooks. Re-run Vibe Signal: Setup Codex Hooks to refresh.",
  hooks,
};
const hooksPath = path.join(os.homedir(), ".codex", "hooks.json");
fs.writeFileSync(hooksPath, JSON.stringify(out, null, 2));
console.log("nodeWin:", nodeWin);
console.log("commandWindows:", winCmd);
console.log("wrote:", hooksPath);
