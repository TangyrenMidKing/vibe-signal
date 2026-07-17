import * as http from "http";
import { WebSocketServer, WebSocket } from "ws";
import type { IncomingMessage } from "http";
import { URL } from "url";
import type { StateMachine } from "./state";
import type { DecisionHub } from "./decisionHub";
import type {
  AckMessage,
  AgentCommand,
  CommandMessage,
  StateSnapshot,
} from "./types";

export interface ConnectorServerOptions {
  port: number;
  token: string;
  state: StateMachine;
  decisions: DecisionHub;
  permissionTimeoutMs: number;
  stopTimeoutMs: number;
  onClientCountChange?: (count: number) => void;
  onStartTurn?: (request: StartTurnRequest) => Promise<boolean>;
  /** Kill the phone-launched Codex terminal / process. */
  onStopTurn?: () => boolean | Promise<boolean>;
}

export interface StartTurnRequest {
  prompt: string;
  sessionId?: string;
  cwd?: string;
}

export class ConnectorServer {
  private httpServer: http.Server;
  private wss: WebSocketServer;
  private clients = new Set<WebSocket>();
  private pingTimer?: NodeJS.Timeout;
  readonly port: number;
  readonly token: string;
  private readonly state: StateMachine;
  private readonly decisions: DecisionHub;
  private readonly permissionTimeoutMs: number;
  private readonly stopTimeoutMs: number;
  private readonly onClientCountChange?: (count: number) => void;
  private readonly onStartTurn?: (request: StartTurnRequest) => Promise<boolean>;
  private readonly onStopTurn?: () => boolean | Promise<boolean>;

  constructor(opts: ConnectorServerOptions) {
    this.port = opts.port;
    this.token = opts.token;
    this.state = opts.state;
    this.decisions = opts.decisions;
    this.permissionTimeoutMs = opts.permissionTimeoutMs;
    this.stopTimeoutMs = opts.stopTimeoutMs;
    this.onClientCountChange = opts.onClientCountChange;
    this.onStartTurn = opts.onStartTurn;
    this.onStopTurn = opts.onStopTurn;

    this.httpServer = http.createServer((req, res) => {
      void this.handleHttp(req, res);
    });

    this.wss = new WebSocketServer({ noServer: true });

    this.httpServer.on("upgrade", (req, socket, head) => {
      const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
      const token = url.searchParams.get("token");
      if (token !== this.token) {
        socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
        socket.destroy();
        return;
      }
      this.wss.handleUpgrade(req, socket, head, (ws) => {
        this.wss.emit("connection", ws, req);
      });
    });

    this.wss.on("connection", (ws) => this.onWsConnection(ws));

    this.state.on("change", (snap: StateSnapshot) => {
      this.broadcast(snap);
    });
  }

  async start(): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      this.httpServer.once("error", reject);
      this.httpServer.listen(this.port, "0.0.0.0", () => resolve());
    });
    this.pingTimer = setInterval(() => {
      const ping = JSON.stringify({ type: "ping", ts: Date.now() });
      for (const ws of this.clients) {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(ping);
        }
      }
    }, 25_000);
  }

  async stop(): Promise<void> {
    if (this.pingTimer) clearInterval(this.pingTimer);
    this.decisions.clear();
    for (const ws of this.clients) {
      ws.close();
    }
    this.clients.clear();
    await new Promise<void>((resolve) => this.wss.close(() => resolve()));
    await new Promise<void>((resolve, reject) => {
      this.httpServer.close((err) => (err ? reject(err) : resolve()));
    });
  }

  clientCount(): number {
    return this.clients.size;
  }

  broadcast(message: object): void {
    const raw = JSON.stringify(message);
    for (const ws of this.clients) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(raw);
      }
    }
  }

  async handleCommand(cmd: CommandMessage): Promise<AckMessage> {
    switch (cmd.command) {
      case "approve": {
        const ok = this.decisions.resolvePermission({ decision: "allow" });
        if (ok) this.resumeAfterDecision("Approved");
        return this.decisionAck("approve", ok);
      }
      case "deny": {
        const ok = this.decisions.resolvePermission({
          decision: "deny",
          message: cmd.text ?? "Denied from Vibe Signal",
        });
        if (ok) this.resumeAfterDecision("Denied");
        return this.decisionAck("deny", ok);
      }
      case "continue": {
        const reason = cmd.text?.trim() || "Continue.";
        const ok = this.decisions.resolveStop({
          decision: "continue",
          reason,
        });
        if (ok) this.resumeAfterDecision(reason);
        return this.decisionAck("continue", ok);
      }
      case "retry": {
        const reason = cmd.text?.trim() || "Retry.";
        const ok = this.decisions.resolveStop({
          decision: "continue",
          reason,
        });
        if (ok) this.resumeAfterDecision(reason);
        return this.decisionAck("retry", ok);
      }
      case "voice_prompt": {
        const text = cmd.text?.trim();
        if (!text) {
          return {
            type: "ack",
            command: "voice_prompt",
            ok: false,
            message: "Missing text",
          };
        }
        // Prefer injecting into the one paused turn (Stop hook long-polling).
        if (this.decisions.resolveStop({ decision: "continue", reason: text })) {
          this.resumeAfterDecision(text);
          return { type: "ack", command: "voice_prompt", ok: true };
        }
        // One thread only: never spawn while Codex is mid-turn.
        const current = this.state.get();
        const canStartTurn =
          current.state === "idle" ||
          current.state === "completed" ||
          current.state === "error";
        if (this.onStartTurn && canStartTurn) {
          const started = await this.onStartTurn({
            prompt: text,
            sessionId: current.sessionId,
            cwd: current.cwd,
          });
          if (started) {
            return { type: "ack", command: "voice_prompt", ok: true };
          }
        }
        return {
          type: "ack",
          command: "voice_prompt",
          ok: false,
          message: canStartTurn
            ? "Could not start a Codex turn on the desktop."
            : "Codex is busy. Only one thread at a time.",
        };
      }
      case "stop": {
        const current = this.state.get().state;
        if (current !== "working" && current !== "waiting") {
          return {
            type: "ack",
            command: "stop",
            ok: false,
            message: "Nothing to stop.",
          };
        }
        // Drop any pending permission/stop waiters so hooks don't hang.
        this.decisions.clear();
        const killed = this.onStopTurn ? await this.onStopTurn() : false;
        // Always leave the active UI state so Watch/iPhone aren't stuck.
        if (killed) {
          this.state.setState("completed", "Stopped from Watch");
        } else {
          // Desktop-started turn we don't own — still mark stopped for clients.
          this.state.setState("completed", "Stopped (desktop turn may still be running)");
        }
        return { type: "ack", command: "stop", ok: true };
      }
      default:
        return {
          type: "ack",
          command: cmd.command as AgentCommand,
          ok: false,
          message: "Unknown command",
        };
    }
  }

  /**
   * After a phone decision, leave waiting/completed immediately so the UI
   * (and a follow-up voice_prompt) cannot treat the turn as still paused.
   */
  private resumeAfterDecision(detail: string): void {
    const current = this.state.get();
    if (current.state === "waiting" || current.state === "completed") {
      this.state.setState("working", detail.slice(0, 80));
    }
  }

  private decisionAck(command: AgentCommand, ok: boolean): AckMessage {
    return ok
      ? { type: "ack", command, ok: true }
      : {
          type: "ack",
          command,
          ok: false,
          message: "Codex is not waiting for a phone command. Start a turn first.",
        };
  }

  private onWsConnection(ws: WebSocket): void {
    this.clients.add(ws);
    this.onClientCountChange?.(this.clients.size);
    ws.send(JSON.stringify(this.state.getSnapshot()));

    ws.on("message", async (data) => {
      try {
        const msg = JSON.parse(String(data)) as CommandMessage | { type: string };
        if (msg.type === "pong") return;
        if (msg.type === "command") {
          const ack = await this.handleCommand(msg as CommandMessage);
          ws.send(JSON.stringify(ack));
        }
      } catch {
        // ignore malformed
      }
    });

    ws.on("close", () => {
      this.clients.delete(ws);
      this.onClientCountChange?.(this.clients.size);
    });
  }

  private isLocal(req: IncomingMessage): boolean {
    const ra = req.socket.remoteAddress ?? "";
    return (
      ra === "127.0.0.1" ||
      ra === "::1" ||
      ra === "::ffff:127.0.0.1"
    );
  }

  private async handleHttp(
    req: IncomingMessage,
    res: http.ServerResponse
  ): Promise<void> {
    const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
    const path = url.pathname;

    // CORS not needed — localhost / WS only
    if (path === "/health") {
      this.json(res, 200, {
        ok: true,
        state: this.state.get().state,
        clients: this.clients.size,
      });
      return;
    }

    if (!this.isLocal(req)) {
      this.json(res, 403, { ok: false, error: "localhost only" });
      return;
    }

    if (path === "/hook/event" && req.method === "POST") {
      const body = await readJson(req);
      const event = String(body.hook_event_name ?? "");
      const turnId =
        typeof body.turn_id === "string"
          ? body.turn_id
          : typeof body.session_id === "string"
            ? body.session_id
            : "default";
      if (event === "PermissionRequest") {
        this.decisions.beginPermission(turnId);
      } else if (event === "Stop") {
        this.decisions.beginStop(turnId);
      }
      this.state.applyHookEvent(body);
      this.json(res, 200, { ok: true });
      return;
    }

    if (path === "/decision/permission" && req.method === "GET") {
      const turnId = url.searchParams.get("turn_id") ?? "default";
      const timeoutMs = Number(
        url.searchParams.get("timeout_ms") ?? this.permissionTimeoutMs
      );
      const decision = await this.decisions.waitPermission(turnId, timeoutMs);
      this.clearExpiredDecisionState(turnId, "waiting", decision.decision);
      this.json(res, 200, decision);
      return;
    }

    if (path === "/decision/stop" && req.method === "GET") {
      const turnId = url.searchParams.get("turn_id") ?? "default";
      const timeoutMs = Number(
        url.searchParams.get("timeout_ms") ?? this.stopTimeoutMs
      );
      const decision = await this.decisions.waitStop(turnId, timeoutMs);
      this.clearExpiredDecisionState(turnId, "completed", decision.decision);
      this.json(res, 200, decision);
      return;
    }

    this.json(res, 404, { ok: false, error: "not found" });
  }

  /**
   * The phone should never keep offering actions after a hook's decision
   * window has expired. Only reset the exact turn that timed out—new Codex
   * activity may already have updated the state while the request was open.
   */
  private clearExpiredDecisionState(
    turnId: string,
    expectedState: "waiting" | "completed",
    decision: string
  ): void {
    const current = this.state.get();
    const sameTurn =
      current.turnId === turnId ||
      current.sessionId === turnId ||
      (!current.turnId && turnId === "default");
    if (
      decision === "timeout" &&
      sameTurn &&
      current.state === expectedState
    ) {
      this.state.setState("idle", "Waiting for agent");
    }
  }

  private json(res: http.ServerResponse, status: number, body: object): void {
    const raw = JSON.stringify(body);
    res.writeHead(status, {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(raw),
    });
    res.end(raw);
  }
}

function readJson(req: IncomingMessage): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (c) => chunks.push(c as Buffer));
    req.on("end", () => {
      try {
        const raw = Buffer.concat(chunks).toString("utf8") || "{}";
        resolve(JSON.parse(raw) as Record<string, unknown>);
      } catch (err) {
        reject(err);
      }
    });
    req.on("error", reject);
  });
}
