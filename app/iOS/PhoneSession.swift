import Foundation
import WatchConnectivity

@MainActor
final class PhoneSession: NSObject, WCSessionDelegate {
    private weak var appModel: AppModel?
    private var session: WCSession?
    /// Must retain transfers or WatchConnectivity can cancel them.
    private var outstandingTransfers: [WCSessionFileTransfer] = []

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

    func push(state: StateSnapshot, connected: Bool, ttsPending: Bool = false) {
        guard canPushToWatch else { return }
        guard let session else { return }

        var payload = state.wcPayload
        // Use NSNumber so WatchConnectivity delivers a reliable bool on Watch.
        payload[WCKeys.connected] = NSNumber(value: connected)
        if ttsPending {
            payload[WCKeys.ttsPending] = NSNumber(value: true)
        }
        // WatchConnectivity drops oversized contexts; keep a speakable reply slice.
        if let detail = payload[WCKeys.detail] as? String, detail.count > 900 {
            payload[WCKeys.detail] = String(detail.prefix(900))
        }

        // Prefer a live message for completed replies so the watch can react immediately.
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in }
        }

        // Watch may disappear between the guard and this call; swallow that.
        do {
            try session.updateApplicationContext(payload)
        } catch {
            // WCErrorCodeWatchAppNotInstalled / payload too large — ignore.
        }
    }

    func transferSpeakReply(fileURL: URL, stateTs: Int64) {
        guard canPushToWatch, let session else {
            try? FileManager.default.removeItem(at: fileURL)
            appModel?.lastError = "Watch not available for TTS transfer"
            return
        }
        let transfer = session.transferFile(
            fileURL,
            metadata: [
                WCKeys.command: WCKeys.speakReply,
                WCKeys.ts: NSNumber(value: stateTs)
            ]
        )
        outstandingTransfers.append(transfer)
    }

    func notifyWatchSpeechError(_ message: String) {
        guard canPushToWatch, let session, session.isReachable else { return }
        session.sendMessage(
            [WCKeys.speechError: message],
            replyHandler: nil
        ) { _ in }
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

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        Task { @MainActor in
            outstandingTransfers.removeAll { $0 === fileTransfer }
            if let error {
                appModel?.lastError = "Watch TTS transfer failed: \(error.localizedDescription)"
                notifyWatchSpeechError("TTS transfer failed — using Watch voice")
                if let snap = appModel?.snapshot {
                    push(
                        state: snap,
                        connected: appModel?.isConnected ?? false,
                        ttsPending: false
                    )
                }
            }
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        }
    }
}
