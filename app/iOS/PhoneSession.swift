import Foundation
import WatchConnectivity

@MainActor
final class PhoneSession: NSObject, WCSessionDelegate {
    private weak var appModel: AppModel?
    private var session: WCSession?

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func push(state: StateSnapshot, connected: Bool) {
        guard canPushToWatch else { return }
        guard let session else { return }

        var payload = state.wcPayload
        payload[WCKeys.connected] = connected

        // Watch may disappear between the guard and this call; swallow that.
        do {
            try session.updateApplicationContext(payload)
        } catch {
            // WCErrorCodeWatchAppNotInstalled / not reachable — ignore.
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in }
        }
    }

    private var canPushToWatch: Bool {
        guard let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else {
            return false
        }
        return true
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // Watch app install / uninstall — no action; next push() re-checks.
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard let raw = message[WCKeys.command] as? String,
                  let command = AgentCommand(rawValue: raw) else { return }
            let text = message[WCKeys.text] as? String
            appModel?.handleWatchCommand(command, text: text)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[WCKeys.command] as? String == AgentCommand.voice_prompt.rawValue else { return }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-prompt-\(UUID().uuidString)")
            .appendingPathExtension(file.fileURL.pathExtension)
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: destination)
        } catch {
            return
        }
        Task { @MainActor in
            appModel?.handleWatchRecording(at: destination)
        }
    }
}
