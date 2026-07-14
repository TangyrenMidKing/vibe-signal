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

  constructor(opts: ConnectorServerOptions) {
    this.port = opts.port;
    this.token = opts.token;
    this.state = opts.state;
    this.decisions = opts.decisions;
    this.permissionTimeoutMs = opts.permissionTimeoutMs;
    this.stopTimeoutMs = opts.stopTimeoutMs;
    this.onClientCountChange = opts.onClientCountChange;

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

  handleCommand(cmd: CommandMessage): AckMessage {
    switch (cmd.command) {
      case "approve":
        this.decisions.resolvePermission({ decision: "allow" });
        return { type: "ack", command: "approve", ok: true };
      case "deny":
        this.decisions.resolvePermission({
          decision: "deny",
          message: cmd.text ?? "Denied from AgentPulse",
        });
        return { type: "ack", command: "deny", ok: true };
      case "continue":
        this.decisions.resolveStop({
          decision: "continue",
          reason: cmd.text?.trim() || "Continue.",
        });
        return { type: "ack", command: "continue", ok: true };
      case "retry":
        this.decisions.resolveStop({
          decision: "continue",
          reason: cmd.text?.trim() || "Retry.",
        });
        return { type: "ack", command: "retry", ok: true };
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
        this.decisions.resolveStop({ decision: "continue", reason: text });
        return { type: "ack", command: "voice_prompt", ok: true };
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

  private onWsConnection(ws: WebSocket): void {
    this.clients.add(ws);
    this.onClientCountChange?.(this.clients.size);
    ws.send(JSON.stringify(this.state.getSnapshot()));

    ws.on("message", (data) => {
      try {
        const msg = JSON.parse(String(data)) as CommandMessage | { type: string };
        if (msg.type === "pong") return;
        if (msg.type === "command") {
          const ack = this.handleCommand(msg as CommandMessage);
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
      this.state.applyHookEvent(body);
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
      this.json(res, 200, { ok: true });
      return;
    }

    if (path === "/decision/permission" && req.method === "GET") {
      const turnId = url.searchParams.get("turn_id") ?? "default";
      const timeoutMs = Number(
        url.searchParams.get("timeout_ms") ?? this.permissionTimeoutMs
      );
      this.decisions.beginPermission(turnId);
      const decision = await this.decisions.waitPermission(turnId, timeoutMs);
      this.json(res, 200, decision);
      return;
    }

    if (path === "/decision/stop" && req.method === "GET") {
      const turnId = url.searchParams.get("turn_id") ?? "default";
      const timeoutMs = Number(
        url.searchParams.get("timeout_ms") ?? this.stopTimeoutMs
      );
      this.decisions.beginStop(turnId);
      const decision = await this.decisions.waitStop(turnId, timeoutMs);
      this.json(res, 200, decision);
      return;
    }

    this.json(res, 404, { ok: false, error: "not found" });
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
