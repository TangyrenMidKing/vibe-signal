import { spawn } from "child_process";
import type { ChildProcess } from "child_process";
import type { StartTurnRequest } from "./server";

/**
 * Starts a non-interactive Codex turn from a phone prompt.
 *
 * The prompt is written to stdin instead of interpolated into a shell command,
 * so spoken text cannot be interpreted by PowerShell/bash. When a hook supplied
 * a session id, resume that conversation; otherwise start a new one in the
 * workspace.
 */
export function launchCodexTurn(request: StartTurnRequest): Promise<boolean> {
  const prompt = request.prompt.trim();
  if (!prompt) return Promise.resolve(false);

  const sessionId = validSessionId(request.sessionId)
    ? request.sessionId
    : undefined;
  const args = sessionId
    ? ["exec", "resume", sessionId, "-"]
    : ["exec", "-"];

  return new Promise((resolve) => {
    let child: ChildProcess;
    try {
      child = spawn("codex", args, {
        cwd: request.cwd || undefined,
        // npm installs expose codex.cmd/codex.ps1 on Windows. A shell resolves
        // that shim; user-controlled prompt text never enters this command.
        shell: process.platform === "win32",
        windowsHide: true,
        stdio: ["pipe", "ignore", "ignore"],
      });
    } catch {
      resolve(false);
      return;
    }

    let settled = false;
    const finish = (ok: boolean): void => {
      if (settled) return;
      settled = true;
      resolve(ok);
    };

    child.once("spawn", () => {
      child.stdin?.end(prompt, "utf8");
      child.unref();
      finish(true);
    });
    child.once("error", () => finish(false));
  });
}

function validSessionId(value?: string): value is string {
  return Boolean(
    value &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  );
}
