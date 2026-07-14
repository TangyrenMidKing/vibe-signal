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
        guard let session, session.activationState == .activated else { return }
        var payload = state.wcPayload
        payload[WCKeys.connected] = connected
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in }
        }
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

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard let raw = message[WCKeys.command] as? String,
                  let command = AgentCommand(rawValue: raw) else { return }
            let text = message[WCKeys.text] as? String
            appModel?.handleWatchCommand(command, text: text)
        }
    }
}
