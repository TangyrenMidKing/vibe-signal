import * as vscode from "vscode";
import type { PairingPayload } from "./types";

/**
 * Shows a webview with a QR code encoding the pairing payload.
 * Uses qrcodejs via CDN so we don't bundle a QR library in the extension.
 */
export function showPairingPanel(
  context: vscode.ExtensionContext,
  payload: PairingPayload
): void {
  const panel = vscode.window.createWebviewPanel(
    "agentpulsePairing",
    "AgentPulse Pair Device",
    vscode.ViewColumn.One,
    { enableScripts: true, retainContextWhenHidden: true }
  );

  const json = JSON.stringify(payload);
  const escaped = json.replace(/</g, "\\u003c");
  const hostLine = `${payload.host}:${payload.port}`;

  panel.webview.html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>AgentPulse Pairing</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: var(--vscode-editor-background);
      --fg: var(--vscode-editor-foreground);
      --muted: var(--vscode-descriptionForeground);
      --card: var(--vscode-sideBar-background);
      --accent: var(--vscode-button-background);
    }
    body {
      font-family: var(--vscode-font-family), system-ui, sans-serif;
      background: var(--bg);
      color: var(--fg);
      margin: 0;
      padding: 32px;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 16px;
    }
    h1 { font-size: 20px; font-weight: 600; margin: 0; }
    p { margin: 0; color: var(--muted); text-align: center; max-width: 360px; line-height: 1.45; }
    .card {
      background: #fff;
      border-radius: 16px;
      padding: 20px;
      box-shadow: 0 8px 32px rgba(0,0,0,.18);
    }
    #qrcode { width: 220px; height: 220px; }
    #qrcode img, #qrcode canvas { display: block; }
    .meta {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 13px;
      background: var(--card);
      padding: 12px 16px;
      border-radius: 8px;
      width: min(420px, 100%);
      word-break: break-all;
    }
    .label { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: .06em; margin-bottom: 4px; }
    button {
      background: var(--accent);
      color: var(--vscode-button-foreground);
      border: none;
      border-radius: 6px;
      padding: 8px 14px;
      cursor: pointer;
      font-size: 13px;
    }
  </style>
</head>
<body>
  <h1>Scan with AgentPulse</h1>
  <p>Open the iPhone app and scan this QR code while your phone is on the same Wi‑Fi.</p>
  <div class="card"><div id="qrcode"></div></div>
  <div class="meta">
    <div class="label">Host</div>
    <div>${hostLine}</div>
  </div>
  <div class="meta">
    <div class="label">Token</div>
    <div id="token">${payload.token}</div>
  </div>
  <button id="copy">Copy pairing JSON</button>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
  <script>
    const payload = ${escaped};
    new QRCode(document.getElementById('qrcode'), {
      text: JSON.stringify(payload),
      width: 220,
      height: 220,
      correctLevel: QRCode.CorrectLevel.M
    });
    document.getElementById('copy').addEventListener('click', async () => {
      const text = JSON.stringify(payload);
      try {
        await navigator.clipboard.writeText(text);
        document.getElementById('copy').textContent = 'Copied';
      } catch (e) {
        const ta = document.createElement('textarea');
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        ta.remove();
        document.getElementById('copy').textContent = 'Copied';
      }
    });
  </script>
</body>
</html>`;

  context.subscriptions.push(panel);
}
