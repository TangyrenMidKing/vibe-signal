import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";

function hookCommandUnix(hookScript: string, port: number): string {
  return `node "${hookScript}" --port ${port}`;
}

function hookCommandWindows(hookScript: string, port: number): string {
  const win = hookScript.replace(/\//g, "\\");
  return `node "${win}" --port ${port}`;
}

function makeHandler(hookScript: string, port: number, statusMessage: string) {
  return {
    type: "command",
    command: hookCommandUnix(hookScript, port),
    commandWindows: hookCommandWindows(hookScript, port),
    timeout: 180,
    statusMessage,
  };
}

function isAgentPulseGroup(group: Record<string, unknown>): boolean {
  const hooks = group.hooks as Array<Record<string, unknown>> | undefined;
  if (!Array.isArray(hooks)) return false;
  return hooks.some((h) => {
    const cmd = String(h.command ?? "");
    const cmdWin = String(h.commandWindows ?? "");
    const status = String(h.statusMessage ?? "");
    return (
      cmd.includes(".agentpulse") ||
      cmdWin.includes(".agentpulse") ||
      status.includes("AgentPulse")
    );
  });
}

/**
 * Non-destructively merge AgentPulse hooks into ~/.codex/hooks.json
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

  const codexDir = path.join(os.homedir(), ".codex");
  fs.mkdirSync(codexDir, { recursive: true });
  const hooksPath = path.join(codexDir, "hooks.json");

  let existing: { hooks?: Record<string, unknown[]> } = { hooks: {} };
  if (fs.existsSync(hooksPath)) {
    try {
      existing = JSON.parse(fs.readFileSync(hooksPath, "utf8"));
    } catch {
      const backup = hooksPath + `.bak-${Date.now()}`;
      fs.copyFileSync(hooksPath, backup);
      existing = { hooks: {} };
    }
  }
  if (!existing.hooks || typeof existing.hooks !== "object") {
    existing.hooks = {};
  }

  const events: Array<{ name: string; status: string; matcher?: string }> = [
    { name: "SessionStart", status: "session" },
    { name: "UserPromptSubmit", status: "prompt" },
    { name: "PreToolUse", status: "tool", matcher: "*" },
    { name: "PostToolUse", status: "tool result", matcher: "*" },
    { name: "PermissionRequest", status: "approval", matcher: "*" },
    { name: "Stop", status: "stop" },
  ];

  for (const ev of events) {
    const list = Array.isArray(existing.hooks[ev.name])
      ? (existing.hooks[ev.name] as Array<Record<string, unknown>>)
      : [];

    const filtered = list.filter((g) => !isAgentPulseGroup(g));
    const entry: Record<string, unknown> = {
      hooks: [makeHandler(hookDest, port, `AgentPulse ${ev.status}`)],
    };
    if (ev.matcher) {
      entry.matcher = ev.matcher;
    }
    filtered.push(entry);
    existing.hooks[ev.name] = filtered;
  }

  const out = {
    _comment:
      "Managed partially by AgentPulse. Re-run Setup Codex Hooks to refresh AgentPulse entries.",
    hooks: existing.hooks,
  };

  fs.writeFileSync(hooksPath, JSON.stringify(out, null, 2), "utf8");
  return { hooksPath, hookScript: hookDest };
}

export async function guideHookTrust(): Promise<void> {
  const choice = await vscode.window.showInformationMessage(
    "AgentPulse hooks installed. In Codex CLI, run /hooks and trust the new AgentPulse entries before they will fire.",
    "Open ~/.codex",
    "OK"
  );
  if (choice === "Open ~/.codex") {
    const dir = path.join(os.homedir(), ".codex");
    await vscode.commands.executeCommand("revealFileInOS", vscode.Uri.file(dir));
  }
}
