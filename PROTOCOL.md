# Vibe Signal Protocol v0.1

Single source of truth for WebSocket messages and the local hook HTTP contract between the VS Code connector and clients (iPhone, hook scripts, simulators).

## States

| State       | Color  | Meaning                                      |
|-------------|--------|----------------------------------------------|
| `working`   | red    | Agent is actively planning / coding / editing |
| `waiting`   | yellow | Needs user approval or input                 |
| `completed` | green  | Turn finished successfully                   |
| `error`     | red+   | Failure or non-zero tool result (best-effort)|
| `idle`      | gray   | No active session / disconnected             |

## Commands (phone → connector)

| Command        | Meaning                                              |
|----------------|------------------------------------------------------|
| `approve`      | Allow pending `PermissionRequest`                    |
| `deny`         | Deny pending `PermissionRequest` (Cancel in MVP)     |
| `continue`     | Send a default continue prompt via `Stop` hook       |
| `retry`        | Same as continue with a "retry" reason               |
| `voice_prompt` | Free-text prompt injected via `Stop` hook            |

---

## WebSocket (LAN)

### Connection

```
ws://<lan-ip>:<port>/?token=<pairing-token>
```

- Server binds to `0.0.0.0` (all interfaces) on a chosen port (default `8787`).
- Auth: query `token` must match the connector pairing token. Mismatch → close `4401`.
- Keepalive: server sends JSON ping every 25s; client should reply with `{ "type": "pong" }`.

### Server → Client

**State snapshot** (pushed on change and on connect):

```json
{
  "type": "state",
  "state": "working | waiting | completed | error | idle",
  "detail": "Human-readable summary",
  "sessionId": "optional-codex-session-id",
  "turnId": "optional-turn-id",
  "project": "Jareturn",
  "repo": "owner/jareturn",
  "cwd": "D:\\\\Code\\\\Jareturn",
  "ts": 1710000000000
}
```

`project` is typically the workspace / folder name. `repo` is the git remote identity (`owner/name`) when available, otherwise the git root folder name.
**Ping**:

```json
{ "type": "ping", "ts": 1710000000000 }
```

**Ack** (optional confirmation of a command):

```json
{
  "type": "ack",
  "command": "approve",
  "ok": true,
  "message": "optional"
}
```

### Client → Server

**Command**:

```json
{
  "type": "command",
  "command": "approve | deny | continue | retry | voice_prompt",
  "text": "optional free text for voice_prompt / continue",
  "id": "optional client request id"
}
```

**Pong**:

```json
{ "type": "pong" }
```

---

## Pairing QR payload

Scanned by the iPhone app. JSON string:

```json
{
  "v": 1,
  "name": "Vibe Signal",
  "host": "192.168.1.42",
  "port": 8787,
  "token": "hex-or-base64url-secret"
}
```

---

## Hook HTTP endpoint (localhost only)

Base URL: `http://127.0.0.1:<port>` (same port as WebSocket server).

Only accepts connections from `127.0.0.1`.

### `POST /hook/event`

Body: Codex hook stdin JSON (passthrough), plus any fields the connector adds.

Response:

```json
{ "ok": true }
```

The connector maps `hook_event_name` to agent state:

| Codex event          | Vibe Signal state |
|----------------------|------------------|
| `SessionStart`       | `working`        |
| `UserPromptSubmit`   | `working`        |
| `PreToolUse`         | `working`        |
| `PostToolUse`        | `working` (or `error` if Bash exit ≠ 0) |
| `PermissionRequest`  | `waiting`        |
| `Stop`               | `completed`      |
| `SubagentStop`       | `working`        |

### `GET /decision/permission?turn_id=...&timeout_ms=120000`

Long-poll while a `PermissionRequest` is pending.

Responses:

```json
{ "decision": "allow" }
```

```json
{ "decision": "deny", "message": "Denied from watch" }
```

```json
{ "decision": "timeout" }
```

### `GET /decision/stop?turn_id=...&timeout_ms=60000`

Long-poll after a `Stop` event so the phone can inject a continuation.

Responses:

```json
{ "decision": "timeout" }
```

```json
{
  "decision": "continue",
  "reason": "Continue."
}
```

```json
{
  "decision": "continue",
  "reason": "Use Tailwind and add unit tests."
}
```

### `GET /health`

```json
{ "ok": true, "state": "idle", "clients": 0 }
```

---

## Hook script → Codex stdout mapping

When `/decision/permission` returns `allow` / `deny`, the hook prints:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": { "behavior": "allow" }
  }
}
```

or

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "Denied from Vibe Signal"
    }
  }
}
```

When `/decision/stop` returns `continue`, the hook prints:

```json
{
  "decision": "block",
  "reason": "<reason text>"
}
```

On timeout, the hook exits `0` with no stdout so Codex continues its normal UI flow.
