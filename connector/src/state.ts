import { EventEmitter } from "events";
import type { AgentState, StateSnapshot } from "./types";

export interface InternalState {
  state: AgentState;
  detail: string;
  sessionId?: string;
  turnId?: string;
  ts: number;
}

/**
 * Maps Codex hook / simulator events into the four AgentPulse UI states.
 */
export class StateMachine extends EventEmitter {
  private current: InternalState = {
    state: "idle",
    detail: "Waiting for agent",
    ts: Date.now(),
  };

  getSnapshot(): StateSnapshot {
    return {
      type: "state",
      state: this.current.state,
      detail: this.current.detail,
      sessionId: this.current.sessionId,
      turnId: this.current.turnId,
      ts: this.current.ts,
    };
  }

  get(): InternalState {
    return { ...this.current };
  }

  setState(
    state: AgentState,
    detail: string,
    meta?: { sessionId?: string; turnId?: string }
  ): StateSnapshot {
    this.current = {
      state,
      detail,
      sessionId: meta?.sessionId ?? this.current.sessionId,
      turnId: meta?.turnId ?? this.current.turnId,
      ts: Date.now(),
    };
    const snap = this.getSnapshot();
    this.emit("change", snap);
    return snap;
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
    const meta = { sessionId, turnId };

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
          return this.setState(
            "error",
            `${tool} exited ${exitCode}`,
            meta
          );
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
            ? body.last_assistant_message.slice(0, 100)
            : "Turn completed";
        return this.setState("completed", last, meta);
      }
      case "SubagentStop":
      case "SubagentStart":
        return this.setState("working", event, meta);
      default:
        return this.setState(
          "working",
          event || "Agent activity",
          meta
        );
    }
  }
}
