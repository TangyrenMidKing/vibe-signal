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
    private var pendingLocalSpeakTs: Int64?
    private var session: WCSession?
    private let synthesizer = AVSpeechSynthesizer()
    private var replyPlayer: AVAudioPlayer?

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
        let ttsPending = dict[WCKeys.ttsPending] as? Bool ?? false
        if let snap = StateSnapshot.fromWC(dict) {
            let prev = snapshot.state
            snapshot = snap
            if prev != snap.state {
                playHaptic(for: snap.state)
            }
            // Prefer OpenAI TTS audio from iPhone; fall back to on-watch speech.
            if snap.state == .completed, lastSpokenResponseTimestamp != snap.ts {
                scheduleReplySpeech(detail: snap.detail, ts: snap.ts, preferOpenAI: ttsPending)
            }
        }
        if let connected = dict[WCKeys.connected] as? Bool {
            phoneConnected = connected
        }
        if let error = dict[WCKeys.speechError] as? String, !error.isEmpty {
            speechError = error
            WKInterfaceDevice.current().play(.failure)
            // TTS failed on phone — speak locally if we were waiting for audio.
            if let ts = pendingLocalSpeakTs, ts == snapshot.ts {
                speakLocal(snapshot.detail, ts: ts)
            }
        }
    }

    func playReplyAudio(at url: URL, ts: Int64) {
        // Cancel local fallback for this reply.
        if pendingLocalSpeakTs == ts {
            pendingLocalSpeakTs = nil
        }
        lastSpokenResponseTimestamp = ts
        stopSpeaking()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.volume = 1
            replyPlayer = player
            guard player.play() else {
                speakLocal(snapshot.detail, ts: ts)
                return
            }
            WKInterfaceDevice.current().play(.success)
            speechError = nil
        } catch {
            speechError = "Couldn't play reply audio"
            speakLocal(snapshot.detail, ts: ts)
        }
    }

    func replayResponse() {
        speakLocal(snapshot.detail, ts: snapshot.ts)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        replyPlayer?.stop()
        replyPlayer = nil
    }

    private func scheduleReplySpeech(detail: String, ts: Int64, preferOpenAI: Bool) {
        lastSpokenResponseTimestamp = ts
        pendingLocalSpeakTs = ts
        let delay: TimeInterval = preferOpenAI ? 8.0 : 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // Still waiting for OpenAI audio / not spoken yet.
            guard self.pendingLocalSpeakTs == ts else { return }
            self.speakLocal(detail, ts: ts)
        }
    }

    private func speakLocal(_ response: String, ts: Int64) {
        guard pendingLocalSpeakTs == ts || lastSpokenResponseTimestamp == ts else { return }
        pendingLocalSpeakTs = nil

        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let skip = ["Done", "Turn completed", "Waiting for agent", "Listening for agent"]
        if skip.contains(text) { return }
        if text.count > 480 {
            text = String(text.prefix(480)) + "…"
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {}

        synthesizer.stopSpeaking(at: .immediate)
        replyPlayer?.stop()
        let utterance = AVSpeechUtterance(string: text)
        let lang = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        utterance.voice =
            AVSpeechSynthesisVoice(language: lang)
            ?? AVSpeechSynthesisVoice(language: String(lang.prefix(2)))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
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

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let command = file.metadata?[WCKeys.command] as? String
        guard command == WCKeys.speakReply else { return }
        let ts = (file.metadata?[WCKeys.ts] as? NSNumber)?.int64Value
            ?? Int64(Date().timeIntervalSince1970 * 1_000)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("reply-\(ts)-\(UUID().uuidString)")
            .appendingPathExtension(file.fileURL.pathExtension.isEmpty ? "mp3" : file.fileURL.pathExtension)
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: destination)
        } catch {
            return
        }
        Task { @MainActor in
            playReplyAudio(at: destination, ts: ts)
        }
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
