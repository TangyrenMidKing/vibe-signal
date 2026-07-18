# Vibe Signal

> Let your AI coding agent stay connected when you leave the desk.

**Vibe Signal** is a companion system for AI coding agents. A VS Code extension watches [Codex](https://github.com/openai/codex) via lifecycle hooks, pushes live status over the local Wi‑Fi to your iPhone, and mirrors it to Apple Watch with haptics and Approve / Continue / voice controls.

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

## How we used Codex and GPT-5.6

### Codex powers the product

Vibe Signal is built directly around the **Codex CLI**. Codex lifecycle hooks such as `SessionStart`, `PostToolUse`, `PermissionRequest`, and `Stop` are translated into a small set of live states that can be understood at a glance. When Codex needs input, Vibe Signal sends the decision back from the iPhone or Apple Watch. Voice prompts can also start or continue a Codex turn, completing the loop from wrist to coding agent.

This is more than a status display: Codex is the active agent behind the experience, while Vibe Signal provides a mobile control and notification layer around it.

### GPT-5.6 helped us build it

We used **GPT-5.6 in Cursor** as an engineering collaborator throughout development. It helped us:

- Design the local-first architecture and shared WebSocket protocol
- Implement the TypeScript VS Code connector and native SwiftUI apps
- Debug state synchronization across Codex, iPhone, and Apple Watch
- Work through iOS background execution, WatchConnectivity, speech, and audio lifecycle issues
- Create tests, refine the demo flow, and document the project

GPT-5.6 was especially valuable when changes crossed multiple platforms. It could reason about the connector, protocol, and Apple clients together instead of treating each component as an isolated codebase.

## Built with

TypeScript, Node.js, Swift, SwiftUI, iOS, watchOS, Apple Watch, VS Code Extension API, Codex CLI, GPT-5.6, WebSockets, WatchConnectivity, AVFoundation, Speech Recognition, UserNotifications, URLSession, QR pairing, Xcode, and XcodeGen.

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
3. In the Extension Development Host, confirm the status bar shows `Vibe Signal: idle`

### Sidebar UI

Click the **Vibe Signal** pulse icon in the Activity Bar:

- Toggle **Connector On/Off** (server only listens when On)
- Live state, detail, client count, host:port, token, health URL
- Buttons for pair QR, copy pairing JSON, Codex hooks, simulate, rotate token

Status bar shows Off / current state; click it to open the sidebar.

### Useful commands

| Command | Purpose |
|---------|---------|
| **Vibe Signal: Toggle Connector** | Enable / disable the LAN server |
| **Vibe Signal: Open Sidebar** | Focus the Vibe Signal panel |
| **Vibe Signal: Pair Device** | QR webview for iPhone |
| **Vibe Signal: Setup Codex Hooks** | Merge hooks into `~/.codex/hooks.json` |
| **Vibe Signal: Simulate Event** | Drive states without Codex |
| **Vibe Signal: Copy Pairing Info** | Copy host/port/token JSON |
| **Vibe Signal: Show Status** | Modal status dump |

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
2. Run **Vibe Signal: Setup Codex Hooks**.
3. This copies `hooks/hook.js` → `~/.agentpulse/hook.js` and merges Vibe Signal entries into `~/.codex/hooks.json`.
4. In Codex CLI, run **`/hooks`**, review, and **trust** the Vibe Signal command hooks.
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
open VibeSignal.xcodeproj
```

### Xcode steps

1. Select your **Team** under Signing for both `VibeSignal` and `VibeSignalWatch`.
2. Set a unique bundle id if `com.vibesignal.app` is taken.
3. Run the **VibeSignal** scheme on a physical iPhone (camera + local network; Watch optional).
4. Install the Watch app from the Phone’s Watch app if needed.

### Pairing

1. On desktop: **Vibe Signal: Pair Device**.
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
