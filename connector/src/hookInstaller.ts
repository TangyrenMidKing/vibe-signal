import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { execFileSync } from "child_process";
import * as vscode from "vscode";

function resolveNodeBinary(): { unix: string; windows: string } {
  try {
    if (process.platform === "win32") {
      const out = execFileSync("where.exe", ["node"], {
        encoding: "utf8",
        windowsHide: true,
      })
        .split(/\r?\n/)
        .map((s) => s.trim())
        .find((s) => s.toLowerCase().endsWith("node.exe"));
      if (out) {
        return { unix: "node", windows: out };
      }
    } else {
      const out = execFileSync("which", ["node"], { encoding: "utf8" }).trim();
      if (out) {
        return { unix: out, windows: "node" };
      }
    }
  } catch {
    // fall through
  }
  const programFiles = process.env.ProgramFiles || "C:\\Program Files";
  const guess = path.join(programFiles, "nodejs", "node.exe");
  if (fs.existsSync(guess)) {
    return { unix: "node", windows: guess };
  }
  return { unix: "node", windows: "node" };
}

function makeHandler(
  hookScript: string,
  windowsCmd: string,
  port: number,
  statusMessage: string
) {
  const node = resolveNodeBinary();
  const unixHook = hookScript.replace(/\\/g, "/");
  return {
    type: "command",
    command: `${node.unix} "${unixHook}" --port ${port}`,
    // Prefer a no-space wrapper .cmd so Codex argv parsing cannot break on Program Files.
    commandWindows: windowsCmd,
    timeout: 180,
    statusMessage,
  };
}

function isVibeSignalGroup(group: Record<string, unknown>): boolean {
  const hooks = group.hooks as Array<Record<string, unknown>> | undefined;
  if (!Array.isArray(hooks)) return false;
  return hooks.some((h) => {
    const cmd = String(h.command ?? "");
    const cmdWin = String(h.commandWindows ?? "");
    const status = String(h.statusMessage ?? "");
    return (
      cmd.includes(".agentpulse") ||
      cmdWin.includes(".agentpulse") ||
      cmdWin.includes("run-hook.cmd") ||
      status.includes("Vibe Signal") ||
      status.includes("AgentPulse")
    );
  });
}

/**
 * Non-destructively merge Vibe Signal hooks into ~/.codex/hooks.json
 */
export async function installCodexHooks(
  context: vscode.ExtensionContext,
  port: number
): Promise<{ hooksPath: string; hookScript: string }> {
  const hookSrc = path.join(context.extensionPath, "hooks", "hook.js");
  if (!fs.existsSync(hookSrc)) {
    throw new Error(`Missing hook script at ${hookSrc}`);
  }

  const userDir = path.join(os.homedir(), ".agentpulse");
  fs.mkdirSync(userDir, { recursive: true });
  const hookDest = path.join(userDir, "hook.js");
  fs.copyFileSync(hookSrc, hookDest);
  fs.writeFileSync(path.join(userDir, "port"), String(port), "utf8");

  const node = resolveNodeBinary();
  const winCmd = path.join(userDir, "run-hook.cmd");
  fs.writeFileSync(
    winCmd,
    [
      "@echo off",
      `"${node.windows.replace(/\//g, "\\")}" "%~dp0hook.js" --port ${port}`,
      "",
    ].join("\r\n"),
    "utf8"
  );

  const codexDir = path.join(os.homedir(), ".codex");
  fs.mkdirSync(codexDir, { recursive: true });
  const hooksPath = path.join(codexDir, "hooks.json");

  let existing: { hooks?: Record<string, unknown[]>; description?: string } = {
    hooks: {},
  };
  if (fs.existsSync(hooksPath)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(hooksPath, "utf8")) as {
        hooks?: Record<string, unknown[]>;
        description?: string;
      };
      existing = {
        hooks: parsed.hooks,
        description: parsed.description,
      };
    } catch {
      const backup = hooksPath + `.bak-${Date.now()}`;
      fs.copyFileSync(hooksPath, backup);
      existing = { hooks: {} };
    }
  }
  if (!existing.hooks || typeof existing.hooks !== "object") {
    existing.hooks = {};
  }

  const events: Array<{ name: string; status: string }> = [
    { name: "SessionStart", status: "session" },
    { name: "UserPromptSubmit", status: "prompt" },
    { name: "PreToolUse", status: "tool" },
    { name: "PostToolUse", status: "tool result" },
    { name: "PermissionRequest", status: "approval" },
    { name: "Stop", status: "stop" },
  ];

  for (const ev of events) {
    const list = Array.isArray(existing.hooks[ev.name])
      ? (existing.hooks[ev.name] as Array<Record<string, unknown>>)
      : [];

    const filtered = list.filter((g) => !isVibeSignalGroup(g));
    filtered.push({
      hooks: [makeHandler(hookDest, winCmd, port, `Vibe Signal ${ev.status}`)],
    });
    existing.hooks[ev.name] = filtered;
  }

  const out = {
    description:
      "Includes Vibe Signal companion hooks. Re-run Vibe Signal: Setup Codex Hooks to refresh.",
    hooks: existing.hooks,
  };

  fs.writeFileSync(hooksPath, JSON.stringify(out, null, 2), "utf8");
  return { hooksPath, hookScript: hookDest };
}

export async function guideHookTrust(): Promise<void> {
  const choice = await vscode.window.showInformationMessage(
    "Vibe Signal hooks updated. In Codex, run /hooks — if anything needs review, Trust all again (definitions changed).",
    "Open ~/.codex",
    "OK"
  );
  if (choice === "Open ~/.codex") {
    const dir = path.join(os.homedir(), ".codex");
    await vscode.commands.executeCommand("revealFileInOS", vscode.Uri.file(dir));
  }
}
