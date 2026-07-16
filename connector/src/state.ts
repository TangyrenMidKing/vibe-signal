import { EventEmitter } from "events";
import type { AgentState, StateSnapshot } from "./types";
import { resolveProjectRepo } from "./projectInfo";

export interface InternalState {
  state: AgentState;
  detail: string;
  sessionId?: string;
  turnId?: string;
  project?: string;
  repo?: string;
  cwd?: string;
  ts: number;
}

export interface StateMeta {
  sessionId?: string;
  turnId?: string;
  project?: string;
  repo?: string;
  cwd?: string;
}

export interface StateMachineOptions {
  /** Reset a stale active turn when its terminal Stop hook never arrives. */
  workingTimeoutMs?: number;
}

/**
 * Maps Codex hook / simulator events into the four Vibe Signal UI states.
 */
export class StateMachine extends EventEmitter {
  private readonly workingTimeoutMs: number;
  private workingTimeout?: NodeJS.Timeout;
  private current: InternalState = {
    state: "idle",
    detail: "Waiting for agent",
    ts: Date.now(),
  };

  constructor(options: StateMachineOptions = {}) {
    super();
    this.workingTimeoutMs = Math.max(1, options.workingTimeoutMs ?? 600_000);
  }

  getSnapshot(): StateSnapshot {
    return {
      type: "state",
      state: this.current.state,
      detail: this.current.detail,
      sessionId: this.current.sessionId,
      turnId: this.current.turnId,
      project: this.current.project,
      repo: this.current.repo,
      cwd: this.current.cwd,
      ts: this.current.ts,
    };
  }

  get(): InternalState {
    return { ...this.current };
  }

  setState(state: AgentState, detail: string, meta?: StateMeta): StateSnapshot {
    this.clearWorkingTimeout();
    this.current = {
      state,
      detail,
      sessionId: meta?.sessionId ?? this.current.sessionId,
      turnId: meta?.turnId ?? this.current.turnId,
      project: meta?.project ?? this.current.project,
      repo: meta?.repo ?? this.current.repo,
      cwd: meta?.cwd ?? this.current.cwd,
      ts: Date.now(),
    };
    const snap = this.getSnapshot();
    this.emit("change", snap);
    if (state === "working") {
      this.scheduleWorkingTimeout(snap.ts);
    }
    return snap;
  }

  dispose(): void {
    this.clearWorkingTimeout();
  }

  private scheduleWorkingTimeout(ts: number): void {
    this.workingTimeout = setTimeout(() => {
      if (this.current.state === "working" && this.current.ts === ts) {
        this.setState("idle", "Waiting for agent");
      }
    }, this.workingTimeoutMs);
    this.workingTimeout.unref();
  }

  private clearWorkingTimeout(): void {
    if (this.workingTimeout) {
      clearTimeout(this.workingTimeout);
      this.workingTimeout = undefined;
    }
  }

  /**
   * Seed project/repo from the VS Code workspace (before any Codex hook).
   */
  seedWorkspace(folderPath?: string, folderName?: string): void {
    if (!folderPath && !folderName) return;
    const info = resolveProjectRepo(folderPath);
    this.current = {
      ...this.current,
      project: info.project ?? folderName ?? this.current.project,
      repo: info.repo ?? this.current.repo,
      cwd: info.cwd ?? folderPath ?? this.current.cwd,
      ts: Date.now(),
    };
    this.emit("change", this.getSnapshot());
  }

  /**
   * Apply a Codex hook event body.
   */
  applyHookEvent(body: Record<string, unknown>): StateSnapshot {
    const event = String(body.hook_event_name ?? body.type ?? "");
    const sessionId =
      typeof body.session_id === "string" ? body.session_id : undefined;
    const turnId =
      typeof body.turn_id === "string" ? body.turn_id : undefined;
    const cwd = typeof body.cwd === "string" ? body.cwd : undefined;
    const loc = resolveProjectRepo(cwd);
    const meta: StateMeta = {
      sessionId,
      turnId,
      cwd: loc.cwd ?? cwd,
      project: loc.project,
      repo: loc.repo,
    };

    switch (event) {
      case "SessionStart":
        return this.setState("working", "Session started", meta);
      case "UserPromptSubmit": {
        const prompt =
          typeof body.prompt === "string" ? body.prompt.slice(0, 80) : "New prompt";
        return this.setState("working", prompt, meta);
      }
      case "PreToolUse": {
        const tool =
          typeof body.tool_name === "string" ? body.tool_name : "tool";
        return this.setState("working", `Using ${tool}`, meta);
      }
      case "PostToolUse": {
        const tool =
          typeof body.tool_name === "string" ? body.tool_name : "tool";
        const response = body.tool_response as Record<string, unknown> | undefined;
        const exitCode =
          response && typeof response.exit_code === "number"
            ? response.exit_code
            : response && typeof response.exitCode === "number"
              ? response.exitCode
              : undefined;
        if (typeof exitCode === "number" && exitCode !== 0) {
          return this.setState("error", `${tool} exited ${exitCode}`, meta);
        }
        return this.setState("working", `Finished ${tool}`, meta);
      }
      case "PermissionRequest": {
        const tool =
          typeof body.tool_name === "string" ? body.tool_name : "tool";
        const input = body.tool_input as Record<string, unknown> | undefined;
        const cmd =
          input && typeof input.command === "string"
            ? input.command.slice(0, 100)
            : undefined;
        const desc =
          input && typeof input.description === "string"
            ? input.description.slice(0, 100)
            : undefined;
        const detail = desc ?? (cmd ? `Approve: ${cmd}` : `Approve ${tool}`);
        return this.setState("waiting", detail, meta);
      }
      case "Stop": {
        const last =
          typeof body.last_assistant_message === "string"
            ? body.last_assistant_message.slice(0, 8_000)
            : "Turn completed";
        return this.setState("completed", last, meta);
      }
      case "SubagentStop":
      case "SubagentStart":
        return this.setState("working", event, meta);
      default:
        return this.setState("working", event || "Agent activity", meta);
    }
  }
}
