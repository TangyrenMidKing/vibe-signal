import * as vscode from "vscode";
import type { ConnectorController, PanelInfo } from "./controller";

/**
 * Activity-bar webview: on/off toggle, live status, and setup checklist.
 */
export class VibeSignalSidebarProvider implements vscode.WebviewViewProvider {
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
        case "markTrusted":
          await this.controller.markHooksTrusted();
          break;
        case "dismissSetup":
          await this.controller.dismissSetup();
          break;
        case "showSetup":
          await this.controller.resetSetup();
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
      this.view.description = info.enabled ? info.state : "Off";
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
  <title>Vibe Signal</title>
  <style>
    :root {
      color-scheme: light dark;
      --gap: 12px;
      --radius: 10px;
    }
    * { box-sizing: border-box; }
    html, body {
      width: 100%;
      max-width: 100%;
      overflow-x: hidden;
    }
    body {
      margin: 0;
      padding: 12px 12px 20px;
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
    .hero, .card, .setup, .next-bar {
      padding: 12px;
      border-radius: var(--radius);
      background: var(--vscode-editor-background);
      border: 1px solid var(--vscode-widget-border, transparent);
      margin-bottom: var(--gap);
      width: 100%;
      max-width: 100%;
      overflow: hidden;
    }
    .row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
    }
    .title { font-size: 16px; font-weight: 650; }
    .sub { font-size: 12px; opacity: 0.7; margin-top: 2px; }
    .toggle {
      position: relative;
      width: 52px; height: 28px;
      border-radius: 999px;
      cursor: pointer;
      background: var(--vscode-input-background);
      border: 1px solid var(--vscode-widget-border, rgba(127,127,127,.35));
      padding: 0; flex-shrink: 0;
    }
    .toggle.on {
      background: var(--vscode-button-background);
      border-color: transparent;
    }
    .toggle .knob {
      position: absolute; top: 2px; left: 2px;
      width: 22px; height: 22px; border-radius: 50%;
      background: #fff; transition: transform .15s ease;
      box-shadow: 0 1px 3px rgba(0,0,0,.25);
    }
    .toggle.on .knob { transform: translateX(24px); }
    .badge {
      display: inline-flex; align-items: center; gap: 6px;
      font-size: 12px; font-weight: 600;
      text-transform: uppercase; letter-spacing: .05em;
      padding: 4px 8px; border-radius: 999px;
      background: color-mix(in srgb, var(--state) 18%, transparent);
    }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--state); }
    .label {
      font-size: 10px; text-transform: uppercase;
      letter-spacing: .07em; opacity: 0.6; margin-bottom: 4px;
    }
    .value {
      font-family: var(--vscode-editor-font-family), ui-monospace, monospace;
      font-size: 12px; word-break: break-all; line-height: 1.4;
    }
    .detail { margin-top: 8px; font-size: 12.5px; opacity: 0.85; line-height: 1.4; }
    .actions { display: grid; gap: 8px; }
    button.btn {
      width: 100%; text-align: left;
      border: 1px solid var(--vscode-button-border, transparent);
      background: var(--vscode-button-secondaryBackground, var(--vscode-button-background));
      color: var(--vscode-button-secondaryForeground, var(--vscode-button-foreground));
      border-radius: 6px; padding: 8px 10px; cursor: pointer; font-size: 12.5px;
    }
    button.btn:hover { filter: brightness(1.08); }
    button.btn.primary {
      background: var(--vscode-button-background);
      color: var(--vscode-button-foreground);
      text-align: center; font-weight: 600;
    }
    button.btn:disabled { opacity: 0.45; cursor: not-allowed; }
    button.linkish {
      background: none; border: none; color: var(--vscode-textLink-foreground);
      cursor: pointer; font-size: 11px; padding: 0; text-align: left;
    }
    .error { margin-top: 8px; color: var(--vscode-errorForeground); font-size: 12px; }
    .muted { opacity: 0.55; font-size: 11px; }
    .setup-head {
      display: flex; align-items: flex-start; justify-content: space-between;
      gap: 8px; margin-bottom: 10px;
    }
    .setup-title { font-size: 13px; font-weight: 650; }
    .setup-progress { font-size: 11px; opacity: 0.65; margin-top: 2px; }
    .steps { display: grid; gap: 8px; }
    .step {
      display: grid;
      grid-template-columns: 22px minmax(0, 1fr);
      gap: 8px;
      padding: 8px;
      border-radius: 8px;
      border: 1px solid transparent;
      background: transparent;
      max-width: 100%;
      min-width: 0;
    }
    .step > div:last-child { min-width: 0; }
    .step.active {
      border-color: var(--vscode-focusBorder, var(--vscode-button-background));
      background: color-mix(in srgb, var(--vscode-button-background) 12%, transparent);
    }
    .step.done { opacity: 0.72; }
    .step-num {
      width: 22px; height: 22px; border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      font-size: 11px; font-weight: 700;
      background: var(--vscode-badge-background);
      color: var(--vscode-badge-foreground);
      flex-shrink: 0;
    }
    .step.done .step-num {
      background: #3fb950; color: #fff;
    }
    .step.active .step-num {
      background: var(--vscode-button-background);
      color: var(--vscode-button-foreground);
    }
    .step-title { font-size: 12.5px; font-weight: 600; }
    .step-desc { font-size: 11.5px; opacity: 0.75; margin-top: 2px; line-height: 1.4; }
    .step-cta { margin-top: 8px; display: grid; gap: 6px; }
    .hint {
      margin-top: 10px; padding: 8px 10px; border-radius: 6px;
      background: color-mix(in srgb, var(--vscode-inputValidation-infoBorder, #3794ff) 16%, transparent);
      font-size: 11.5px; line-height: 1.45;
    }
    code {
      font-family: var(--vscode-editor-font-family), ui-monospace, monospace;
      font-size: 11px;
      padding: 1px 4px;
      border-radius: 4px;
      background: var(--vscode-textCodeBlock-background, rgba(127,127,127,.15));
    }
    .next-bar {
      border-color: var(--vscode-focusBorder, transparent);
      background: color-mix(in srgb, var(--vscode-button-background) 14%, var(--vscode-editor-background));
    }
    .next-label { font-size: 10px; text-transform: uppercase; letter-spacing: .06em; opacity: .65; }
    .next-title { font-size: 14px; font-weight: 650; margin-top: 2px; }
    .next-desc { font-size: 12px; opacity: .8; margin: 4px 0 10px; line-height: 1.4; }
    [hidden] { display: none !important; }
  </style>
</head>
<body>
  <h1>Vibe Signal</h1>

  <div class="next-bar" id="nextBar">
    <div class="next-label">Next step</div>
    <div class="next-title" id="nextTitle">Turn the connector on</div>
    <div class="next-desc" id="nextDesc">Enable Vibe Signal so your phone and Codex can connect.</div>
    <button class="btn primary" id="nextBtn">Turn On</button>
  </div>

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

  <div class="setup" id="setupCard">
    <div class="setup-head">
      <div>
        <div class="setup-title">Setup guide</div>
        <div class="setup-progress" id="setupProgress">0 / 4 complete</div>
      </div>
      <button class="linkish" id="dismissSetup">Hide</button>
    </div>
    <div class="steps">
      <div class="step" data-step="1" id="step1">
        <div class="step-num">1</div>
        <div>
          <div class="step-title">Turn connector On</div>
          <div class="step-desc">Starts the LAN WebSocket so your iPhone can connect.</div>
          <div class="step-cta" data-cta="1">
            <button class="btn primary" id="ctaEnable">Turn On</button>
          </div>
        </div>
      </div>
      <div class="step" data-step="2" id="step2">
        <div class="step-num">2</div>
        <div>
          <div class="step-title">Install Codex hooks</div>
          <div class="step-desc">Writes Vibe Signal entries into <code>~/.codex/hooks.json</code>.</div>
          <div class="step-cta" data-cta="2">
            <button class="btn primary" id="ctaHooks">Setup Codex Hooks</button>
          </div>
        </div>
      </div>
      <div class="step" data-step="3" id="step3">
        <div class="step-num">3</div>
        <div>
          <div class="step-title">Trust hooks in Codex</div>
          <div class="step-desc">In Codex CLI run <code>/hooks</code>, review Vibe Signal, and trust them. Skipping this means no status events.</div>
          <div class="step-cta" data-cta="3">
            <button class="btn primary" id="ctaTrusted">I've trusted hooks</button>
            <div class="hint">Open a Codex terminal → type <code>/hooks</code> → trust every Vibe Signal command.</div>
          </div>
        </div>
      </div>
      <div class="step" data-step="4" id="step4">
        <div class="step-num">4</div>
        <div>
          <div class="step-title">Pair iPhone (same Wi‑Fi)</div>
          <div class="step-desc">Scan the QR from the phone app. Clients count should become 1+.</div>
          <div class="step-cta" data-cta="4">
            <button class="btn primary" id="ctaPair">Show Pairing QR</button>
            <button class="btn" id="ctaCopy">Copy Pairing JSON</button>
          </div>
        </div>
      </div>
    </div>
    <div class="hint" id="setupDoneHint" hidden>
      Setup complete. Start a Codex turn — Watch/iPhone should flip to Working / Waiting / Completed.
      Use <b>Simulate Event</b> below to try the phone UI without Codex.
    </div>
  </div>

  <div class="card" id="setupCollapsedBar" hidden>
    <div class="row">
      <div>
        <div class="label">Setup</div>
        <div class="value" id="setupCollapsedLabel">Guide hidden</div>
      </div>
      <button class="linkish" id="showSetupAgain">Show guide</button>
    </div>
  </div>

  <div class="card">
    <div class="label">Project</div>
    <div class="value" id="project">—</div>
    <div style="height:8px"></div>
    <div class="label">Repo</div>
    <div class="value" id="repo">—</div>
    <div style="height:8px"></div>
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
    <button class="btn" id="pair" data-cmd="agentpulse.pairDevice">Pair Device (QR)</button>
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

    const nextCopy = {
      1: {
        title: 'Turn the connector on',
        desc: 'Enable Vibe Signal so your phone and Codex can connect.',
        btn: 'Turn On',
        action: () => vscode.postMessage({ type: 'setEnabled', enabled: true })
      },
      2: {
        title: 'Install Codex hooks',
        desc: 'This lets Codex push Working / Waiting / Completed into Vibe Signal.',
        btn: 'Setup Codex Hooks',
        action: () => vscode.postMessage({ type: 'command', command: 'agentpulse.setupHooks' })
      },
      3: {
        title: 'Trust hooks in Codex',
        desc: 'In Codex CLI run /hooks and trust the Vibe Signal entries.',
        btn: "I've trusted hooks",
        action: () => vscode.postMessage({ type: 'markTrusted' })
      },
      4: {
        title: 'Pair your iPhone',
        desc: 'Same Wi‑Fi required. Scan the QR — clients should go from 0 → 1.',
        btn: 'Show Pairing QR',
        action: () => vscode.postMessage({ type: 'command', command: 'agentpulse.pairDevice' })
      },
      0: {
        title: 'You are set up',
        desc: 'Run Codex or Simulate Event to see live status on your watch.',
        btn: 'Simulate Event',
        action: () => vscode.postMessage({ type: 'command', command: 'agentpulse.simulateEvent' })
      }
    };

    function doneCount(info) {
      let n = 0;
      if (info.enabled) n++;
      if (info.setup.hooksInstalled) n++;
      if (info.setup.hooksTrusted) n++;
      if (info.clients > 0) n++;
      return n;
    }

    function render(info) {
      const setup = info.setup || {};
      document.getElementById('toggle').classList.toggle('on', info.enabled);
      document.getElementById('toggle').setAttribute('aria-pressed', String(info.enabled));
      document.getElementById('modeTitle').textContent = info.enabled ? 'Connector On' : 'Connector Off';
      document.getElementById('modeSub').textContent = info.enabled
        ? (info.listening ? 'Broadcasting on LAN' : 'Starting…')
        : 'Toggle on to listen for Codex & phones';
      document.getElementById('stateText').textContent = info.state;
      document.getElementById('stateBadge').style.setProperty('--state', colors[info.state] || colors.idle);
      document.getElementById('clients').textContent =
        info.clients + (info.clients === 1 ? ' client' : ' clients');
      document.getElementById('detail').textContent = info.detail || '—';
      document.getElementById('project').textContent = info.project || '—';
      document.getElementById('repo').textContent = info.repo || '—';
      document.getElementById('host').textContent = info.host + ':' + info.port;
      document.getElementById('token').textContent = info.tokenMasked;
      document.getElementById('health').textContent = info.healthUrl;

      const err = document.getElementById('error');
      if (info.lastError) {
        err.hidden = false;
        err.textContent = info.lastError;
      } else {
        err.hidden = true;
      }

      const disabled = !info.enabled;
      ['pair','copy','hooks','sim'].forEach((id) => {
        document.getElementById(id).disabled = disabled;
      });

      // Setup checklist
      const completeFlags = {
        1: info.enabled,
        2: setup.hooksInstalled,
        3: setup.hooksTrusted,
        4: info.clients > 0
      };
      const current = setup.currentStep || 0;
      const showGuide = !setup.dismissed;
      document.getElementById('setupCard').hidden = !showGuide;
      document.getElementById('setupCollapsedBar').hidden = showGuide;
      document.getElementById('setupCollapsedLabel').textContent = setup.complete
        ? 'Complete'
        : (doneCount(info) + ' / 4 · guide hidden');
      document.getElementById('setupProgress').textContent =
        doneCount(info) + ' / 4 complete';
      document.getElementById('setupDoneHint').hidden = !setup.complete;

      for (let i = 1; i <= 4; i++) {
        const el = document.getElementById('step' + i);
        el.classList.toggle('done', completeFlags[i]);
        el.classList.toggle('active', current === i && !setup.complete);
        el.querySelector('.step-num').textContent = completeFlags[i] ? '✓' : String(i);
        const cta = el.querySelector('[data-cta]');
        if (cta) cta.hidden = current !== i || setup.complete;
      }

      // Compact next-step bar: show only while guide is open and incomplete
      const next = nextCopy[current] || nextCopy[0];
      document.getElementById('nextTitle').textContent = next.title;
      document.getElementById('nextDesc').textContent = next.desc;
      const nextBtn = document.getElementById('nextBtn');
      nextBtn.textContent = next.btn;
      nextBtn.onclick = next.action;
      document.getElementById('nextBar').hidden = !showGuide || setup.complete;
    }

    document.getElementById('toggle').addEventListener('click', () => {
      vscode.postMessage({ type: 'toggle' });
    });
    document.getElementById('ctaEnable').addEventListener('click', () => {
      vscode.postMessage({ type: 'setEnabled', enabled: true });
    });
    document.getElementById('ctaHooks').addEventListener('click', () => {
      vscode.postMessage({ type: 'command', command: 'agentpulse.setupHooks' });
    });
    document.getElementById('ctaTrusted').addEventListener('click', () => {
      vscode.postMessage({ type: 'markTrusted' });
    });
    document.getElementById('ctaPair').addEventListener('click', () => {
      vscode.postMessage({ type: 'command', command: 'agentpulse.pairDevice' });
    });
    document.getElementById('ctaCopy').addEventListener('click', () => {
      vscode.postMessage({ type: 'command', command: 'agentpulse.copyPairingInfo' });
    });
    document.getElementById('dismissSetup').addEventListener('click', () => {
      vscode.postMessage({ type: 'dismissSetup' });
    });
    document.getElementById('showSetupAgain').addEventListener('click', () => {
      vscode.postMessage({ type: 'showSetup' });
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
