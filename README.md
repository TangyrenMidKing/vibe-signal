# AgentPulse

> Let your AI coding agent stay connected when you leave the desk.

**AgentPulse** is a companion system for AI coding agents. A VS Code extension watches [Codex](https://github.com/openai/codex) via lifecycle hooks, pushes live status over the local Wi‑Fi to your iPhone, and mirrors it to Apple Watch with haptics and Approve / Continue / voice controls.

```
Codex CLI ──hooks──► VS Code Extension (connector)
                              │
                     WebSocket (same Wi‑Fi)
                              │
                           iPhone
                              │
                      WatchConnectivity
                              │
                         Apple Watch
```

See [PROTOCOL.md](PROTOCOL.md) for the wire formats.

## Repo layout

| Path | Role |
|------|------|
| [`connector/`](connector/) | VS Code extension — local HTTP + LAN WebSocket + Codex hook installer |
| [`app/`](app/) | SwiftUI iPhone + Apple Watch sources (build on a Mac) |
| [`PROTOCOL.md`](PROTOCOL.md) | Shared message contracts |

## MVP features

- Red / yellow / green status on Watch and iPhone (`working` / `waiting` / `completed`)
- Distinct haptics per state change
- Approve / Deny for Codex `PermissionRequest`
- Continue / Retry / voice prompt after `Stop`
- Same-WiFi realtime sync via QR pairing

---

## 1. Desktop connector (VS Code)

### Requirements

- Node.js 18+
- VS Code (or Cursor with VS Code extension compatibility)
- Codex CLI with hooks enabled

### Install / run from source

```bash
cd connector
npm install
npm run compile
```

In VS Code: **Extensions → … → Install from VSIX…** after packaging, or use the Extension Development Host:

1. Open the `connector` folder in VS Code
2. Press `F5` (Run Extension)
3. In the Extension Development Host, confirm the status bar shows `AgentPulse: idle`

### Sidebar UI

Click the **AgentPulse** pulse icon in the Activity Bar:

- Toggle **Connector On/Off** (server only listens when On)
- Live state, detail, client count, host:port, token, health URL
- Buttons for pair QR, copy pairing JSON, Codex hooks, simulate, rotate token

Status bar shows Off / current state; click it to open the sidebar.

### Useful commands

| Command | Purpose |
|---------|---------|
| **AgentPulse: Toggle Connector** | Enable / disable the LAN server |
| **AgentPulse: Open Sidebar** | Focus the AgentPulse panel |
| **AgentPulse: Pair Device** | QR webview for iPhone |
| **AgentPulse: Setup Codex Hooks** | Merge hooks into `~/.codex/hooks.json` |
| **AgentPulse: Simulate Event** | Drive states without Codex |
| **AgentPulse: Copy Pairing Info** | Copy host/port/token JSON |
| **AgentPulse: Show Status** | Modal status dump |

Settings (`agentpulse.*`):

- `port` (default `8787`)
- `permissionTimeoutMs` (default `120000`)
- `stopTimeoutMs` (default `60000`)

### Dev harness (no VS Code)

```bash
cd connector
npm run compile
# PowerShell
$env:AGENTPULSE_TOKEN='test-token-mvp'; node scripts/dev-server.js
# then
node scripts/ws-client.js 127.0.0.1 8787 test-token-mvp
```

---

## 2. Wire Codex hooks

1. Start the extension (so the port is listening).
2. Run **AgentPulse: Setup Codex Hooks**.
3. This copies `hooks/hook.js` → `~/.agentpulse/hook.js` and merges AgentPulse entries into `~/.codex/hooks.json`.
4. In Codex CLI, run **`/hooks`**, review, and **trust** the AgentPulse command hooks.
5. Start a Codex turn — status should move to **working**, approvals to **waiting**, finish to **completed**.

Without trust, Codex skips the hooks silently.

**Cancel** in MVP = Deny a pending permission request (Codex has no interrupt-via-hook).

---

## 3. iPhone + Apple Watch app

Sources live under [`app/`](app/). They must be compiled on a Mac with Xcode 15+ (iOS 17 / watchOS 10).

### Generate the Xcode project

```bash
# on macOS
brew install xcodegen   # once
cd app
xcodegen generate
open AgentPulse.xcodeproj
```

### Xcode steps

1. Select your **Team** under Signing for both `AgentPulse` and `AgentPulseWatch`.
2. Set a unique bundle id if `com.agentpulse.app` is taken.
3. Run the **AgentPulse** scheme on a physical iPhone (camera + local network; Watch optional).
4. Install the Watch app from the Phone’s Watch app if needed.

### Pairing

1. On desktop: **AgentPulse: Pair Device**.
2. On phone: scan the QR (or paste JSON / enter host + port + token).
3. Phone and desktop must be on the **same Wi‑Fi**. Status becomes **Live**.
4. Watch updates automatically via WatchConnectivity while the iPhone app is paired/reachable.

### Permissions

- Camera (QR)
- Microphone + Speech (voice prompts)
- Local Network (LAN WebSocket)

---

## States & controls

| State | Color | Typical trigger | Watch actions |
|-------|-------|-----------------|---------------|
| Working | Red | Session / prompt / tool use | Mic |
| Waiting | Yellow | `PermissionRequest` | Approve / Deny |
| Completed | Green | `Stop` | Continue / Mic |
| Error | Orange | Best-effort non-zero Bash | Continue / Mic |

Haptics: start (working), triple notification (waiting), failure (error), success (completed).

---

## Phase 2 / 3 (not in MVP)

Dynamic Island, menu bar app, cloud relay, internet remote, multi-device.

---

## License

MIT (or your choice once published).
