import * as vscode from "vscode";
import { ConnectorController, type PanelInfo } from "./controller";
import { AgentPulseSidebarProvider } from "./sidebar";
import { showPairingPanel } from "./pairing";
import { installCodexHooks, guideHookTrust } from "./hookInstaller";
import type { AgentState } from "./types";

let controller: ConnectorController | undefined;
let statusBar: vscode.StatusBarItem | undefined;

function stateIcon(s: AgentState): string {
  switch (s) {
    case "working":
      return "$(sync~spin)";
    case "waiting":
      return "$(warning)";
    case "completed":
      return "$(check)";
    case "error":
      return "$(error)";
    default:
      return "$(watch)";
  }
}

function refreshStatusBar(info: PanelInfo): void {
  if (!statusBar) return;
  // Keep text short so it is less likely to hide behind the status-bar overflow (`…`).
  if (!info.enabled) {
    statusBar.text = "$(pulse) AgentPulse Off";
    statusBar.tooltip =
      "AgentPulse is off — click to open the sidebar and turn it on";
    statusBar.backgroundColor = new vscode.ThemeColor(
      "statusBarItem.prominentBackground"
    );
    statusBar.color = new vscode.ThemeColor(
      "statusBarItem.prominentForeground"
    );
    return;
  }
  statusBar.text = `${stateIcon(info.state)} AgentPulse ${info.state}${
    info.clients ? ` · ${info.clients}` : ""
  }`;
  statusBar.tooltip = `${info.detail}\nLAN ${info.host}:${info.port}\nClients: ${info.clients}\nClick to open panel`;
  statusBar.backgroundColor =
    info.state === "waiting"
      ? new vscode.ThemeColor("statusBarItem.warningBackground")
      : undefined;
  statusBar.color = undefined;
}

export async function activate(
  context: vscode.ExtensionContext
): Promise<void> {
  controller = new ConnectorController(context);
  const sidebar = new AgentPulseSidebarProvider(controller);

  // Stable id + Right alignment so it shows next to the clock / far-right cluster
  // and can be re-enabled from the status-bar context menu if hidden.
  statusBar = vscode.window.createStatusBarItem(
    "agentpulse.status",
    vscode.StatusBarAlignment.Right,
    1000
  );
  statusBar.name = "AgentPulse";
  statusBar.command = "agentpulse.focusSidebar";
  statusBar.accessibilityInformation = {
    label: "AgentPulse connector status",
  };
  refreshStatusBar({
    enabled: false,
    listening: false,
    state: "idle",
    detail: "AgentPulse is off",
    host: "—",
    port: 8787,
    token: "",
    tokenMasked: "••••",
    clients: 0,
    healthUrl: "http://127.0.0.1:8787/health",
    ts: Date.now(),
  });
  statusBar.show();

  controller.on("change", (info: PanelInfo) => refreshStatusBar(info));

  context.subscriptions.push(
    statusBar,
    vscode.window.registerWebviewViewProvider(
      AgentPulseSidebarProvider.viewType,
      sidebar
    ),
    {
      dispose: () => {
        void controller?.dispose();
      },
    },
    vscode.commands.registerCommand("agentpulse.focusSidebar", async () => {
      await vscode.commands.executeCommand("agentpulse.sidebar.focus");
    }),
    vscode.commands.registerCommand("agentpulse.toggle", async () => {
      if (!controller) return;
      const on = await controller.toggle();
      void vscode.window.showInformationMessage(
        on ? "AgentPulse connector enabled" : "AgentPulse connector disabled"
      );
    }),
    vscode.commands.registerCommand("agentpulse.enable", async () => {
      await controller?.setEnabled(true);
    }),
    vscode.commands.registerCommand("agentpulse.disable", async () => {
      await controller?.setEnabled(false);
    }),
    vscode.commands.registerCommand("agentpulse.pairDevice", () => {
      if (!controller?.isEnabled()) {
        void vscode.window.showWarningMessage(
          "Turn on AgentPulse in the sidebar first."
        );
        return;
      }
      showPairingPanel(context, controller.getPairingPayload());
    }),
    vscode.commands.registerCommand("agentpulse.copyPairingInfo", async () => {
      if (!controller?.isEnabled()) {
        void vscode.window.showWarningMessage(
          "Turn on AgentPulse in the sidebar first."
        );
        return;
      }
      await vscode.env.clipboard.writeText(
        JSON.stringify(controller.getPairingPayload())
      );
      void vscode.window.showInformationMessage(
        "AgentPulse pairing JSON copied."
      );
    }),
    vscode.commands.registerCommand("agentpulse.setupHooks", async () => {
      if (!controller?.isEnabled()) {
        void vscode.window.showWarningMessage(
          "Turn on AgentPulse in the sidebar first."
        );
        return;
      }
      const info = controller.getInfo();
      try {
        const { hooksPath } = await installCodexHooks(context, info.port);
        void vscode.window.showInformationMessage(
          `Codex hooks updated at ${hooksPath}`
        );
        await guideHookTrust();
      } catch (err) {
        void vscode.window.showErrorMessage(
          `Hook setup failed: ${String(err)}`
        );
      }
    }),
    vscode.commands.registerCommand("agentpulse.rotateToken", async () => {
      if (!controller) return;
      const confirm = await vscode.window.showWarningMessage(
        "Rotate pairing token? Connected phones must re-pair.",
        { modal: true },
        "Rotate"
      );
      if (confirm !== "Rotate") return;
      await controller.rotateToken();
      void vscode.window.showInformationMessage(
        "AgentPulse token rotated. Re-pair your device."
      );
    }),
    vscode.commands.registerCommand("agentpulse.showStatus", async () => {
      await vscode.commands.executeCommand("agentpulse.sidebar.focus");
      if (!controller) return;
      const info = controller.getInfo();
      const msg = [
        `Enabled: ${info.enabled}`,
        `State: ${info.state}`,
        `Detail: ${info.detail}`,
        `Host: ${info.host}:${info.port}`,
        `Clients: ${info.clients}`,
        `Health: ${info.healthUrl}`,
      ].join("\n");
      await vscode.window.showInformationMessage(msg, { modal: true });
    }),
    vscode.commands.registerCommand("agentpulse.simulateEvent", async () => {
      if (!controller?.isEnabled()) {
        void vscode.window.showWarningMessage(
          "Turn on AgentPulse in the sidebar first."
        );
        return;
      }
      const pick = await vscode.window.showQuickPick(
        [
          { label: "working", description: "Agent started / coding" },
          { label: "waiting", description: "Needs approval" },
          { label: "completed", description: "Turn finished" },
          { label: "error", description: "Failure" },
          { label: "idle", description: "Reset" },
        ],
        { placeHolder: "Simulate AgentPulse state" }
      );
      if (!pick) return;
      const map: Record<string, { state: AgentState; detail: string }> = {
        working: { state: "working", detail: "Simulated: coding" },
        waiting: {
          state: "waiting",
          detail: "Simulated: approve npm install?",
        },
        completed: { state: "completed", detail: "Simulated: tests passed" },
        error: { state: "error", detail: "Simulated: build failed" },
        idle: { state: "idle", detail: "Waiting for agent" },
      };
      const next = map[pick.label];
      if (!next) return;
      controller.state.setState(next.state, next.detail, {
        sessionId: "sim",
        turnId: `sim-${Date.now()}`,
      });
      if (next.state === "waiting") {
        controller.decisions.beginPermission(`sim-${Date.now()}`);
      } else if (next.state === "completed") {
        controller.decisions.beginStop(`sim-${Date.now()}`);
      }
    })
  );

  await controller.restore();
  refreshStatusBar(controller.getInfo());
}

export function deactivate(): void {
  void controller?.dispose();
}
