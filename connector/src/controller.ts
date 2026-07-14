import { EventEmitter } from "events";
import * as vscode from "vscode";
import { StateMachine } from "./state";
import { DecisionHub } from "./decisionHub";
import { ConnectorServer } from "./server";
import { generateToken, preferredLanAddress } from "./network";
import type { AgentState, PairingPayload, StateSnapshot } from "./types";

const TOKEN_KEY = "agentpulse.pairingToken";
const ENABLED_KEY = "agentpulse.enabled";

export interface PanelInfo {
  enabled: boolean;
  listening: boolean;
  state: AgentState;
  detail: string;
  host: string;
  port: number;
  token: string;
  tokenMasked: string;
  clients: number;
  healthUrl: string;
  sessionId?: string;
  turnId?: string;
  lastError?: string;
  ts: number;
}

/**
 * Owns connector lifecycle: start/stop server, state, UI notifications.
 */
export class ConnectorController extends EventEmitter {
  readonly state: StateMachine;
  readonly decisions: DecisionHub;
  private server?: ConnectorServer;
  private token: string;
  private enabled = false;
  private lastError?: string;
  private readonly context: vscode.ExtensionContext;

  constructor(context: vscode.ExtensionContext) {
    super();
    this.context = context;
    this.state = new StateMachine();
    this.decisions = new DecisionHub();
    this.token = context.globalState.get<string>(TOKEN_KEY) ?? "";
    if (!this.token) {
      this.token = generateToken();
      void context.globalState.update(TOKEN_KEY, this.token);
    }
    this.enabled = context.globalState.get<boolean>(ENABLED_KEY) ?? false;

    this.state.on("change", (snap: StateSnapshot) => {
      this.emit("change", this.getInfo());
      this.emit("state", snap);
    });
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  getInfo(): PanelInfo {
    const port = this.server?.port ?? this.readPort();
    const host = preferredLanAddress();
    const snap = this.state.getSnapshot();
    return {
      enabled: this.enabled,
      listening: Boolean(this.server),
      state: snap.state,
      detail: snap.detail,
      host,
      port,
      token: this.token,
      tokenMasked: maskToken(this.token),
      clients: this.server?.clientCount() ?? 0,
      healthUrl: `http://127.0.0.1:${port}/health`,
      sessionId: snap.sessionId,
      turnId: snap.turnId,
      lastError: this.lastError,
      ts: snap.ts,
    };
  }

  getPairingPayload(): PairingPayload {
    const info = this.getInfo();
    return {
      v: 1,
      name: "AgentPulse",
      host: info.host,
      port: info.port,
      token: this.token,
    };
  }

  async restore(): Promise<void> {
    if (this.enabled) {
      await this.start();
    } else {
      this.emit("change", this.getInfo());
    }
  }

  async setEnabled(enabled: boolean): Promise<void> {
    if (enabled === this.enabled && (!enabled || this.server)) {
      this.emit("change", this.getInfo());
      return;
    }
    this.enabled = enabled;
    await this.context.globalState.update(ENABLED_KEY, enabled);
    if (enabled) {
      await this.start();
    } else {
      await this.stop();
      this.state.setState("idle", "AgentPulse is off");
    }
    this.emit("change", this.getInfo());
  }

  async toggle(): Promise<boolean> {
    await this.setEnabled(!this.enabled);
    return this.enabled;
  }

  async rotateToken(): Promise<void> {
    const wasEnabled = this.enabled;
    if (wasEnabled) {
      await this.stop();
    }
    this.token = generateToken();
    await this.context.globalState.update(TOKEN_KEY, this.token);
    if (wasEnabled) {
      await this.start();
    }
    this.emit("change", this.getInfo());
  }

  async dispose(): Promise<void> {
    await this.stop();
  }

  private readPort(): number {
    return (
      vscode.workspace.getConfiguration("agentpulse").get<number>("port") ??
      8787
    );
  }

  private async start(): Promise<void> {
    if (this.server) return;
    const config = vscode.workspace.getConfiguration("agentpulse");
    const port = config.get<number>("port") ?? 8787;
    const permissionTimeoutMs =
      config.get<number>("permissionTimeoutMs") ?? 120_000;
    const stopTimeoutMs = config.get<number>("stopTimeoutMs") ?? 60_000;

    this.server = new ConnectorServer({
      port,
      token: this.token,
      state: this.state,
      decisions: this.decisions,
      permissionTimeoutMs,
      stopTimeoutMs,
      onClientCountChange: () => this.emit("change", this.getInfo()),
    });

    try {
      await this.server.start();
      this.lastError = undefined;
      if (this.state.get().state === "idle") {
        this.state.setState("idle", "Listening for agent");
      }
    } catch (err) {
      this.lastError = String(err);
      this.server = undefined;
      this.enabled = false;
      await this.context.globalState.update(ENABLED_KEY, false);
      void vscode.window.showErrorMessage(
        `AgentPulse failed to bind port ${port}: ${String(err)}`
      );
    }
  }

  private async stop(): Promise<void> {
    if (!this.server) return;
    try {
      await this.server.stop();
    } catch {
      // ignore shutdown errors
    }
    this.server = undefined;
  }
}

function maskToken(token: string): string {
  if (token.length <= 8) return "••••";
  return `${token.slice(0, 4)}…${token.slice(-4)}`;
}
