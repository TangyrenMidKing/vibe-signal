export type AgentState = "idle" | "working" | "waiting" | "completed" | "error";

export type AgentCommand =
  | "approve"
  | "deny"
  | "continue"
  | "retry"
  | "voice_prompt";

export interface StateSnapshot {
  type: "state";
  state: AgentState;
  detail: string;
  sessionId?: string;
  turnId?: string;
  ts: number;
}

export interface CommandMessage {
  type: "command";
  command: AgentCommand;
  text?: string;
  id?: string;
}

export interface AckMessage {
  type: "ack";
  command: AgentCommand;
  ok: boolean;
  message?: string;
}

export interface PairingPayload {
  v: 1;
  name: "AgentPulse";
  host: string;
  port: number;
  token: string;
}

export type PermissionDecision =
  | { decision: "allow" }
  | { decision: "deny"; message?: string }
  | { decision: "timeout" };

export type StopDecision =
  | { decision: "timeout" }
  | { decision: "continue"; reason: string };
