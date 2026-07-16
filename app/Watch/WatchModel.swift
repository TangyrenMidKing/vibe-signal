import Foundation
import Combine
import WatchConnectivity
import WatchKit
import AVFoundation

@MainActor
final class WatchModel: NSObject, ObservableObject {
    @Published var snapshot = StateSnapshot(state: .idle, detail: "Waiting for iPhone")
    @Published var phoneConnected = false
    @Published var phoneReachable = false
    @Published var speechError: String?

    private var lastHapticState: AgentState?
    private var lastSpokenResponseTimestamp: Int64?
    private var session: WCSession?
    private let synthesizer = AVSpeechSynthesizer()

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func clearSpeechError() {
        speechError = nil
    }

    func send(_ command: AgentCommand, text: String? = nil) {
        guard isCommandWindowOpen(for: command) else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        guard let session, session.isReachable else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        var msg: [String: Any] = [WCKeys.command: command.rawValue]
        if let text { msg[WCKeys.text] = text }
        session.sendMessage(msg, replyHandler: nil) { _ in
            Task { @MainActor in
                WKInterfaceDevice.current().play(.failure)
            }
        }
        WKInterfaceDevice.current().play(.success)
    }

    func sendVoiceRecording(_ url: URL) {
        let linked = phoneReachable || phoneConnected
        guard linked, let session else {
            speechError = "iPhone not reachable"
            WKInterfaceDevice.current().play(.failure)
            try? FileManager.default.removeItem(at: url)
            return
        }
        speechError = nil
        session.transferFile(url, metadata: [WCKeys.command: AgentCommand.voice_prompt.rawValue])
        WKInterfaceDevice.current().play(.success)
    }

    private func isCommandWindowOpen(for command: AgentCommand) -> Bool {
        let ageMs = Int64(Date().timeIntervalSince1970 * 1_000) - snapshot.ts
        // Reachability is enough for the watch; the connected flag can lag
        // behind application-context updates from the phone.
        let linked = phoneReachable || phoneConnected
        switch command {
        case .approve, .deny:
            return linked && snapshot.state == .waiting && ageMs < 115_000
        case .continue, .retry:
            return linked && snapshot.state == .completed && ageMs < 295_000
        case .voice_prompt:
            // One thread only: inject into a paused turn, or start when idle.
            guard linked else { return false }
            switch snapshot.state {
            case .idle, .completed, .error:
                return true
            case .working, .waiting:
                return false
            }
        }
    }

    func apply(_ dict: [String: Any]) {
        if let snap = StateSnapshot.fromWC(dict) {
            let prev = snapshot.state
            snapshot = snap
            if prev != snap.state {
                playHaptic(for: snap.state)
            }
            if snap.state == .completed, lastSpokenResponseTimestamp != snap.ts {
                lastSpokenResponseTimestamp = snap.ts
                speak(snap.detail)
            }
        }
        if let connected = dict[WCKeys.connected] as? Bool {
            phoneConnected = connected
        }
        if let error = dict[WCKeys.speechError] as? String, !error.isEmpty {
            speechError = error
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func replayResponse() {
        speak(snapshot.detail)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speak(_ response: String) {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func playHaptic(for state: AgentState) {
        guard lastHapticState != state else { return }
        lastHapticState = state
        let device = WKInterfaceDevice.current()
        switch state {
        case .working:
            device.play(.start)
        case .waiting:
            device.play(.notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { device.play(.notification) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { device.play(.notification) }
        case .error:
            device.play(.failure)
        case .completed:
            device.play(.success)
        case .idle:
            break
        }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            phoneReachable = session.isReachable
            let ctx = session.receivedApplicationContext
            if !ctx.isEmpty {
                apply(ctx)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in apply(message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                speechError = error.localizedDescription
                WKInterfaceDevice.current().play(.failure)
            }
        }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in phoneReachable = session.isReachable }
    }
}
