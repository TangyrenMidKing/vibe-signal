# AgentPulse Connector

VS Code extension that:

1. Serves a LAN WebSocket for the iPhone app
2. Exposes localhost HTTP for Codex lifecycle hooks
3. Installs / merges hooks into `~/.codex/hooks.json`

## UI

Open the **AgentPulse** icon in the Activity Bar:

- **Toggle** — enable / disable the connector (like Builder Mode)
- **Status** — live agent state, detail, clients
- **Connection** — LAN host:port, masked token, health URL
- **Actions** — Pair QR, copy pairing JSON, setup Codex hooks, simulate events, rotate token

Status bar shows `AgentPulse: Off` or the current state; click it to focus the sidebar.

## See it in VS Code / Cursor

The status bar and Activity Bar icon **only appear when this extension is running**. Source in the repo alone is not enough.

**Option A — Extension Development Host (recommended while coding)**

1. Open the `vibe-signal` repo (or just `connector/`) in VS Code / Cursor
2. `cd connector && npm install && npm run compile`
3. Run **Run and Debug → Run AgentPulse Extension** (or press `F5`)
4. A **new** window opens — look there (not the old window):
   - Activity Bar: pulse icon **AgentPulse**
   - Status bar (bottom-right): **AgentPulse Off**

If the status item is missing, right-click the status bar → enable **AgentPulse**.

**Option B — Install into your normal editor**

```bash
cd connector
npm run compile
npx @vscode/vsce package --no-dependencies
# then: Extensions → … → Install from VSIX… → agentpulse-0.1.0.vsix
```

## Develop

```bash
npm install
npm run compile
```

Press `F5` from the repo root or this folder, or:

```bash
$env:AGENTPULSE_TOKEN='dev'; node scripts/dev-server.js
node scripts/ws-client.js 127.0.0.1 8787 dev
```

## Package

```bash
npm run compile
npx @vscode/vsce package --no-dependencies
```
