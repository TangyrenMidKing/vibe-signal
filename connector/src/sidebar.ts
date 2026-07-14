import * as vscode from "vscode";
import type { ConnectorController, PanelInfo } from "./controller";

/**
 * Activity-bar webview: Builder Mode–style on/off toggle + live status.
 */
export class AgentPulseSidebarProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = "agentpulse.sidebar";

  private view?: vscode.WebviewView;

  constructor(private readonly controller: ConnectorController) {
    controller.on("change", (info: PanelInfo) => this.post(info));
  }

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ): void {
    this.view = webviewView;
    webviewView.webview.options = {
      enableScripts: true,
    };
    webviewView.webview.html = this.html(webviewView.webview);
    webviewView.webview.onDidReceiveMessage(async (msg) => {
      switch (msg?.type) {
        case "ready":
          this.post(this.controller.getInfo());
          break;
        case "toggle":
          await this.controller.toggle();
          break;
        case "setEnabled":
          await this.controller.setEnabled(Boolean(msg.enabled));
          break;
        case "command":
          if (typeof msg.command === "string") {
            await vscode.commands.executeCommand(msg.command);
          }
          break;
      }
    });
    this.post(this.controller.getInfo());
  }

  private post(info: PanelInfo): void {
    void this.view?.webview.postMessage({ type: "info", info });
    if (this.view) {
      this.view.description = info.enabled
        ? info.state
        : "Off";
    }
  }

  private html(webview: vscode.Webview): string {
    const csp = [
      `default-src 'none'`,
      `style-src ${webview.cspSource} 'unsafe-inline'`,
      `script-src ${webview.cspSource} 'unsafe-inline'`,
    ].join("; ");

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>AgentPulse</title>
  <style>
    :root {
      color-scheme: light dark;
      --gap: 12px;
      --radius: 10px;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 14px 14px 20px;
      font-family: var(--vscode-font-family), system-ui, sans-serif;
      font-size: var(--vscode-font-size);
      color: var(--vscode-foreground);
      background: var(--vscode-sideBar-background);
    }
    h1 {
      font-size: 13px;
      font-weight: 600;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      margin: 0 0 4px;
      opacity: 0.75;
    }
    .hero {
      display: flex;
      flex-direction: column;
      gap: 10px;
      padding: 14px;
      border-radius: var(--radius);
      background: var(--vscode-editor-background);
      border: 1px solid var(--vscode-widget-border, transparent);
      margin-bottom: var(--gap);
    }
    .row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
    }
    .title {
      font-size: 16px;
      font-weight: 650;
    }
    .sub {
      font-size: 12px;
      opacity: 0.7;
      margin-top: 2px;
    }
    .toggle {
      position: relative;
      width: 52px;
      height: 28px;
      border: none;
      border-radius: 999px;
      cursor: pointer;
      background: var(--vscode-input-background);
      border: 1px solid var(--vscode-widget-border, rgba(127,127,127,.35));
      padding: 0;
      flex-shrink: 0;
    }
    .toggle.on {
      background: var(--vscode-button-background);
      border-color: transparent;
    }
    .toggle .knob {
      position: absolute;
      top: 2px;
      left: 2px;
      width: 22px;
      height: 22px;
      border-radius: 50%;
      background: #fff;
      transition: transform .15s ease;
      box-shadow: 0 1px 3px rgba(0,0,0,.25);
    }
    .toggle.on .knob { transform: translateX(24px); }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .05em;
      padding: 4px 8px;
      border-radius: 999px;
      background: color-mix(in srgb, var(--state) 18%, transparent);
      color: var(--fg, var(--vscode-foreground));
    }
    .dot {
      width: 8px; height: 8px; border-radius: 50%;
      background: var(--state);
    }
    .card {
      padding: 12px;
      border-radius: var(--radius);
      background: var(--vscode-editor-background);
      border: 1px solid var(--vscode-widget-border, transparent);
      margin-bottom: var(--gap);
    }
    .label {
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: .07em;
      opacity: 0.6;
      margin-bottom: 4px;
    }
    .value {
      font-family: var(--vscode-editor-font-family), ui-monospace, monospace;
      font-size: 12px;
      word-break: break-all;
      line-height: 1.4;
    }
    .detail {
      margin-top: 8px;
      font-size: 12.5px;
      opacity: 0.85;
      line-height: 1.4;
    }
    .actions {
      display: grid;
      gap: 8px;
    }
    button.btn {
      width: 100%;
      text-align: left;
      border: 1px solid var(--vscode-button-border, transparent);
      background: var(--vscode-button-secondaryBackground, var(--vscode-button-background));
      color: var(--vscode-button-secondaryForeground, var(--vscode-button-foreground));
      border-radius: 6px;
      padding: 8px 10px;
      cursor: pointer;
      font-size: 12.5px;
    }
    button.btn:hover { filter: brightness(1.08); }
    button.btn.primary {
      background: var(--vscode-button-background);
      color: var(--vscode-button-foreground);
    }
    button.btn:disabled {
      opacity: 0.45;
      cursor: not-allowed;
    }
    .error {
      margin-top: 8px;
      color: var(--vscode-errorForeground);
      font-size: 12px;
    }
    .muted { opacity: 0.55; font-size: 11px; }
  </style>
</head>
<body>
  <h1>AgentPulse</h1>
  <div class="hero">
    <div class="row">
      <div>
        <div class="title" id="modeTitle">Connector Off</div>
        <div class="sub" id="modeSub">Toggle on to listen for Codex &amp; phones</div>
      </div>
      <button class="toggle" id="toggle" title="Activate / deactivate" aria-pressed="false">
        <span class="knob"></span>
      </button>
    </div>
    <div class="row">
      <span class="badge" id="stateBadge"><span class="dot"></span><span id="stateText">idle</span></span>
      <span class="muted" id="clients">0 clients</span>
    </div>
    <div class="detail" id="detail">—</div>
    <div class="error" id="error" hidden></div>
  </div>

  <div class="card">
    <div class="label">Connection</div>
    <div class="value" id="host">—</div>
    <div style="height:8px"></div>
    <div class="label">Token</div>
    <div class="value" id="token">—</div>
    <div style="height:8px"></div>
    <div class="label">Health</div>
    <div class="value" id="health">—</div>
  </div>

  <div class="actions">
    <button class="btn primary" id="pair" data-cmd="agentpulse.pairDevice">Pair Device (QR)</button>
    <button class="btn" id="copy" data-cmd="agentpulse.copyPairingInfo">Copy Pairing JSON</button>
    <button class="btn" id="hooks" data-cmd="agentpulse.setupHooks">Setup Codex Hooks</button>
    <button class="btn" id="sim" data-cmd="agentpulse.simulateEvent">Simulate Event</button>
    <button class="btn" id="rotate" data-cmd="agentpulse.rotateToken">Rotate Token</button>
  </div>

  <script>
    const vscode = acquireVsCodeApi();
    const colors = {
      idle: '#8b949e',
      working: '#f85149',
      waiting: '#d29922',
      completed: '#3fb950',
      error: '#db6d28'
    };

    const els = {
      toggle: document.getElementById('toggle'),
      modeTitle: document.getElementById('modeTitle'),
      modeSub: document.getElementById('modeSub'),
      stateBadge: document.getElementById('stateBadge'),
      stateText: document.getElementById('stateText'),
      clients: document.getElementById('clients'),
      detail: document.getElementById('detail'),
      host: document.getElementById('host'),
      token: document.getElementById('token'),
      health: document.getElementById('health'),
      error: document.getElementById('error'),
      pair: document.getElementById('pair'),
      copy: document.getElementById('copy'),
      hooks: document.getElementById('hooks'),
      sim: document.getElementById('sim'),
    };

    function render(info) {
      els.toggle.classList.toggle('on', info.enabled);
      els.toggle.setAttribute('aria-pressed', String(info.enabled));
      els.modeTitle.textContent = info.enabled ? 'Connector On' : 'Connector Off';
      els.modeSub.textContent = info.enabled
        ? (info.listening ? 'Broadcasting on LAN' : 'Starting…')
        : 'Toggle on to listen for Codex & phones';
      els.stateText.textContent = info.state;
      els.stateBadge.style.setProperty('--state', colors[info.state] || colors.idle);
      els.clients.textContent = info.clients + (info.clients === 1 ? ' client' : ' clients');
      els.detail.textContent = info.detail || '—';
      els.host.textContent = info.host + ':' + info.port;
      els.token.textContent = info.tokenMasked;
      els.health.textContent = info.healthUrl;
      if (info.lastError) {
        els.error.hidden = false;
        els.error.textContent = info.lastError;
      } else {
        els.error.hidden = true;
      }
      const disabled = !info.enabled;
      [els.pair, els.copy, els.hooks, els.sim].forEach((b) => { b.disabled = disabled; });
    }

    els.toggle.addEventListener('click', () => {
      vscode.postMessage({ type: 'toggle' });
    });
    document.querySelectorAll('[data-cmd]').forEach((btn) => {
      btn.addEventListener('click', () => {
        vscode.postMessage({ type: 'command', command: btn.getAttribute('data-cmd') });
      });
    });
    document.getElementById('rotate').addEventListener('click', () => {
      vscode.postMessage({ type: 'command', command: 'agentpulse.rotateToken' });
    });

    window.addEventListener('message', (e) => {
      const msg = e.data;
      if (msg && msg.type === 'info') render(msg.info);
    });
    vscode.postMessage({ type: 'ready' });
  </script>
</body>
</html>`;
  }
}
