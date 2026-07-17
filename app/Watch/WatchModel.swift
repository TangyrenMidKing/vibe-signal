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
    /// True while OpenAI audio or local TTS is playing — UI shows Stop.
    @Published var isReadingReply = false

    private var lastHapticState: AgentState?
    private var lastSpokenResponseTimestamp: Int64?
    private var pendingLocalSpeakTs: Int64?
    private var session: WCSession?
    private let synthesizer = AVSpeechSynthesizer()
    private var replyPlayer: AVAudioPlayer?
    /// Keep decoded audio alive for background AVAudioPlayer(data:).
    private var replyAudioData: Data?
    /// File-backed playback (mp3) — AVAudioPlayer needs a real file extension.
    private var replyAudioURL: URL?

    func start() {
        guard WCSession.isSupported() else { return }
        synthesizer.delegate = self
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
        case .stop:
            return linked && (snapshot.state == .working || snapshot.state == .waiting)
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
        // WC often boxes Bool as NSNumber — `as? Bool` alone falsely reads false.
        let ttsPending = WCKeys.bool(from: dict, key: WCKeys.ttsPending) ?? false
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
        if let connected = WCKeys.bool(from: dict, key: WCKeys.connected) {
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

    func playReplyAudio(data: Data, ts: Int64, fileExtension: String = "mp3") {
        // Cancel local fallback for this reply.
        pendingLocalSpeakTs = nil
        lastSpokenResponseTimestamp = ts
        synthesizer.stopSpeaking(at: .immediate)
        replyPlayer?.stop()
        replyPlayer = nil
        if let old = replyAudioURL {
            try? FileManager.default.removeItem(at: old)
            replyAudioURL = nil
        }

        guard !data.isEmpty else {
            speechError = "Couldn't play reply audio"
            pendingLocalSpeakTs = ts
            speakLocal(snapshot.detail, ts: ts)
            return
        }
        replyAudioData = data

        let ext = fileExtension.isEmpty ? "mp3" : fileExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reply-\(ts)-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            speechError = "Couldn't save reply audio"
            pendingLocalSpeakTs = ts
            speakLocal(snapshot.detail, ts: ts)
            return
        }
        replyAudioURL = url

        activatePlaybackSession { [weak self] in
            guard let self else { return }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                player.prepareToPlay()
                player.volume = 1
                // duration ~0 means the buffer never decoded (bad format).
                guard player.duration > 0.05 else {
                    self.speechError = "Reply audio unreadable"
                    self.pendingLocalSpeakTs = ts
                    self.speakLocal(self.snapshot.detail, ts: ts)
                    return
                }
                self.replyPlayer = player
                guard player.play() else {
                    self.pendingLocalSpeakTs = ts
                    self.speakLocal(self.snapshot.detail, ts: ts)
                    return
                }
                self.isReadingReply = true
                self.speechError = nil
                WKInterfaceDevice.current().play(.success)
            } catch {
                self.speechError = "Couldn't play reply audio"
                self.pendingLocalSpeakTs = ts
                self.speakLocal(self.snapshot.detail, ts: ts)
            }
        }
    }

    func replayResponse() {
        pendingLocalSpeakTs = snapshot.ts
        speakLocal(snapshot.detail, ts: snapshot.ts)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        replyPlayer?.stop()
        replyPlayer = nil
        replyAudioData = nil
        if let url = replyAudioURL {
            try? FileManager.default.removeItem(at: url)
            replyAudioURL = nil
        }
        pendingLocalSpeakTs = nil
        isReadingReply = false
    }

    private func scheduleReplySpeech(detail: String, ts: Int64, preferOpenAI: Bool) {
        lastSpokenResponseTimestamp = ts
        pendingLocalSpeakTs = ts
        // OpenAI synthesis + WatchConnectivity transfer often needs >8s.
        let delay: TimeInterval = preferOpenAI ? 25.0 : 0.35
        if preferOpenAI {
            speechError = "Loading voice…"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // Still waiting for OpenAI audio / not spoken yet.
            guard self.pendingLocalSpeakTs == ts else { return }
            self.speechError = preferOpenAI ? "Using Watch voice" : nil
            self.speakLocal(detail, ts: ts)
        }
    }

    private func speakLocal(_ response: String, ts: Int64) {
        // Only speak when explicitly scheduled (fallback / replay). Do not
        // re-trigger after OpenAI audio already played for the same ts.
        guard pendingLocalSpeakTs == ts else { return }
        pendingLocalSpeakTs = nil
        lastSpokenResponseTimestamp = ts

        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let skip = ["Done", "Turn completed", "Waiting for agent", "Listening for agent"]
        if skip.contains(text) { return }
        if text.count > 480 {
            text = String(text.prefix(480)) + "…"
        }

        activatePlaybackSession { [weak self] in
            guard let self else { return }
            self.synthesizer.stopSpeaking(at: .immediate)
            self.replyPlayer?.stop()
            let utterance = AVSpeechUtterance(string: text)
            let lang = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
            utterance.voice =
                AVSpeechSynthesisVoice(language: lang)
                ?? AVSpeechSynthesisVoice(language: String(lang.prefix(2)))
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.volume = 1.0
            self.isReadingReply = true
            self.synthesizer.speak(utterance)
        }
    }

    /// watchOS suspends the app when the screen dims unless we own an active
    /// playback session with the Audio background mode enabled.
    private func activatePlaybackSession(then work: @escaping () -> Void) {
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playback, mode: .spokenAudio, options: [])
        } catch {
            try? audio.setCategory(.playback, mode: .default, options: [])
        }
        // activate's completion runs off the main actor. Hop with
        // DispatchQueue.main — Task { @MainActor } + setActive here was
        // triggering unsafeForcedSync / IPCAUClient (-66748).
        audio.activate(options: []) { _, _ in
            DispatchQueue.main.async {
                work()
            }
        }
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

extension WatchModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if replyPlayer === player {
                replyPlayer = nil
                replyAudioData = nil
                if let url = replyAudioURL {
                    try? FileManager.default.removeItem(at: url)
                    replyAudioURL = nil
                }
                isReadingReply = false
            }
        }
    }
}

extension WatchModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in isReadingReply = false }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in isReadingReply = false }
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

        // CRITICAL: read/move before this method returns — WC deletes the inbox
        // file immediately afterward.
        let ext = file.fileURL.pathExtension.isEmpty ? "mp3" : file.fileURL.pathExtension
        let audioData: Data
        do {
            audioData = try Data(contentsOf: file.fileURL)
        } catch {
            return
        }
        guard !audioData.isEmpty else { return }

        Task { @MainActor in
            playReplyAudio(data: audioData, ts: ts, fileExtension: ext)
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
