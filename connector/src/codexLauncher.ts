import * as vscode from "vscode";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { randomUUID } from "crypto";
import type { StartTurnRequest } from "./server";

/** Terminal that shows phone-started Codex turns on the desktop. */
let activeTerminal: vscode.Terminal | undefined;
let starting = false;

/**
 * Starts a Codex turn from a phone prompt in a visible VS Code terminal so
 * the desktop user can watch the full flow.
 *
 * The prompt is written to a temp file and piped into `codex exec` — never
 * interpolated into the shell command — so spoken text cannot be executed as
 * shell. When a hook supplied a session id, resume that conversation;
 * otherwise start a new one in the workspace.
 */
export async function launchCodexTurn(
  request: StartTurnRequest
): Promise<boolean> {
  const prompt = request.prompt.trim();
  if (!prompt) return false;
  if (starting) return false;

  const sessionId = validSessionId(request.sessionId)
    ? request.sessionId
    : undefined;
  const codexArgs = sessionId
    ? `exec resume ${sessionId} -`
    : `exec -`;

  const promptFile = path.join(
    os.tmpdir(),
    `vibe-signal-prompt-${randomUUID()}.txt`
  );
  try {
    fs.writeFileSync(promptFile, prompt, "utf8");
  } catch {
    return false;
  }

  starting = true;
  try {
    // Replace any previous Vibe Signal terminal so only one phone thread shows.
    if (activeTerminal) {
      try {
        activeTerminal.dispose();
      } catch {
        // ignore
      }
      activeTerminal = undefined;
    }

    const preview =
      prompt.length > 48 ? `${prompt.slice(0, 48)}…` : prompt;
    const terminal = vscode.window.createTerminal({
      name: "Vibe Signal",
      cwd: request.cwd || undefined,
      message: `Phone prompt: ${preview}`,
      iconPath: new vscode.ThemeIcon("radio-tower"),
    });
    activeTerminal = terminal;
    terminal.show(true);

    // Let the terminal shell finish starting before we send the command.
    await delay(150);
    terminal.sendText(buildPipeCommand(promptFile, codexArgs), true);

    // Focus the terminal panel so the desktop user sees the turn.
    void vscode.commands.executeCommand(
      "workbench.action.terminal.focus"
    );

    return true;
  } catch {
    try {
      fs.unlinkSync(promptFile);
    } catch {
      // ignore
    }
    return false;
  } finally {
    starting = false;
  }
}

export function isCodexTurnActive(): boolean {
  return starting;
}

/** Drop launcher bookkeeping (e.g. extension deactivate). */
export function releaseCodexTurnLock(): void {
  starting = false;
  if (activeTerminal) {
    try {
      activeTerminal.dispose();
    } catch {
      // ignore
    }
    activeTerminal = undefined;
  }
}

/**
 * Build a shell one-liner that pipes the prompt file into codex, then deletes
 * the temp file. The prompt body never appears in the command string.
 */
function buildPipeCommand(promptFile: string, codexArgs: string): string {
  if (process.platform === "win32") {
    // VS Code's default shell on Windows is PowerShell.
    const p = promptFile.replace(/'/g, "''");
    return (
      `Get-Content -Raw -LiteralPath '${p}' | codex ${codexArgs}; ` +
      `Remove-Item -LiteralPath '${p}' -ErrorAction SilentlyContinue`
    );
  }
  const p = shellSingleQuote(promptFile);
  return `codex ${codexArgs} < ${p}; rm -f ${p}`;
}

function shellSingleQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function validSessionId(value?: string): value is string {
  return Boolean(
    value &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        value
      )
  );
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
