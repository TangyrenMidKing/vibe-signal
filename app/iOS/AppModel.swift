import Foundation
import Combine
import UserNotifications
import WatchConnectivity
import Speech
import Security
import AVFoundation

enum SpeechLanguage: String, CaseIterable, Identifiable {
    case system
    case englishUS = "en-US"
    case englishUK = "en-GB"
    case chineseSimplified = "zh-CN"
    case chineseTraditional = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System default"
        case .englishUS: return "English (US)"
        case .englishUK: return "English (UK)"
        case .chineseSimplified: return "中文（简体）"
        case .chineseTraditional: return "中文（繁體）"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        }
    }

    var localeIdentifier: String {
        guard self != .system else {
            // SFSpeechRecognizer wants BCP-47 (`en-US`); Locale.current often
            // returns underscore form (`en_US`) which silently fails.
            return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        }
        return rawValue
    }
}

enum OpenAIVoice: String, CaseIterable, Identifiable {
    case nova
    case alloy
    case echo
    case fable
    case onyx
    case shimmer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nova: return "Nova"
        case .alloy: return "Alloy"
        case .echo: return "Echo"
        case .fable: return "Fable"
        case .onyx: return "Onyx"
        case .shimmer: return "Shimmer"
        }
    }
}

enum OpenAITTSError: LocalizedError {
    case missingAPIKey
    case badStatus(Int, String)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key in the Vibe Signal menu"
        case .badStatus(let code, let body):
            if code == 429 {
                return "OpenAI TTS quota exceeded — using iPhone voice"
            }
            return "OpenAI TTS failed (\(code)): \(String(body.prefix(80)))"
        case .emptyAudio:
            return "OpenAI TTS returned empty audio"
        }
    }
}

/// On-device Apple TTS on iPhone (enhanced/premium voices) → CAF for Watch.
/// No API key / quota. Much better than Watch's built-in synthesizer.
enum AppleOnDeviceTTS {
    enum TTSError: LocalizedError {
        case emptyAudio
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .emptyAudio: return "iPhone TTS produced no audio"
            case .writeFailed: return "Couldn't write iPhone TTS audio"
            }
        }
    }

    static func synthesizeToFile(_ text: String, languageCode: String) async throws -> URL {
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw TTSError.emptyAudio }
        if input.count > 1200 {
            input = String(input.prefix(1200))
        }

        let renderer = Renderer()
        return try await renderer.render(input, languageCode: languageCode)
    }

    private static func preferredVoice(languageCode: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let prefix = String(languageCode.prefix(2))
        let matching = voices.filter {
            $0.language.replacingOccurrences(of: "_", with: "-")
                .lowercased()
                .hasPrefix(prefix.lowercased())
        }
        if #available(iOS 17.0, *) {
            if let premium = matching.first(where: { $0.quality == .premium }) {
                return premium
            }
        }
        if let enhanced = matching.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        let normalized = languageCode.replacingOccurrences(of: "_", with: "-")
        return AVSpeechSynthesisVoice(language: normalized)
            ?? AVSpeechSynthesisVoice(language: prefix)
            ?? matching.first
    }

    /// Retains synthesizer until write callbacks finish.
    private final class Renderer: @unchecked Sendable {
        private let synthesizer = AVSpeechSynthesizer()
        private let lock = NSLock()
        private var audioFile: AVAudioFile?
        private var outputURL: URL?
        private var continuation: CheckedContinuation<URL, Error>?
        private var finished = false

        func render(_ text: String, languageCode: String) async throws -> URL {
            try await withCheckedThrowingContinuation { cont in
                lock.lock()
                continuation = cont
                lock.unlock()

                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("apple-tts-\(UUID().uuidString)")
                    .appendingPathExtension("caf")
                outputURL = url

                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AppleOnDeviceTTS.preferredVoice(languageCode: languageCode)
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                utterance.volume = 1.0

                synthesizer.write(utterance) { [weak self] buffer in
                    guard let self else { return }
                    guard let pcm = buffer as? AVAudioPCMBuffer else {
                        self.complete()
                        return
                    }
                    if pcm.frameLength == 0 {
                        self.complete()
                        return
                    }
                    do {
                        self.lock.lock()
                        defer { self.lock.unlock() }
                        if self.audioFile == nil {
                            self.audioFile = try AVAudioFile(
                                forWriting: url,
                                settings: pcm.format.settings
                            )
                        }
                        try self.audioFile?.write(from: pcm)
                    } catch {
                        self.fail(error)
                    }
                }
            }
        }

        private func complete() {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let cont = continuation
            continuation = nil
            let url = outputURL
            let wrote = audioFile != nil
            audioFile = nil
            lock.unlock()

            guard let cont, let url, wrote else {
                cont?.resume(throwing: TTSError.emptyAudio)
                return
            }
            // Ensure file is flushed before transfer.
            cont.resume(returning: url)
        }

        private func fail(_ error: Error) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let cont = continuation
            continuation = nil
            if let url = outputURL {
                try? FileManager.default.removeItem(at: url)
            }
            audioFile = nil
            lock.unlock()
            cont?.resume(throwing: error)
        }
    }
}

/// OpenAI Audio Speech API → mp3 for Watch playback.
/// Lives in AppModel.swift so older Xcode projects that list files
/// explicitly still compile without re-running xcodegen.
enum OpenAITTS {
    private static let keychainService = "com.vibesignal.openai"
    private static let keychainAccount = "apiKey"
    private static let voiceDefaultsKey = "vibesignal.openaiVoice"

    static var apiKey: String? {
        get { readKey() }
        set {
            if let newValue, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                saveKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                deleteKey()
            }
        }
    }

    static var hasAPIKey: Bool {
        !(apiKey ?? "").isEmpty
    }

    static var voice: OpenAIVoice {
        get {
            let raw = UserDefaults.standard.string(forKey: voiceDefaultsKey) ?? OpenAIVoice.nova.rawValue
            return OpenAIVoice(rawValue: raw) ?? .nova
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: voiceDefaultsKey)
        }
    }

    static func synthesizeToFile(_ text: String) async throws -> URL {
        guard let key = apiKey, !key.isEmpty else { throw OpenAITTSError.missingAPIKey }

        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw OpenAITTSError.emptyAudio }
        if input.count > 1200 {
            input = String(input.prefix(1200))
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "tts-1-hd",
            "input": input,
            "voice": voice.rawValue,
            // mp3: reliable with AVAudioPlayer. OpenAI "aac" is raw ADTS (not m4a)
            // and produces empty buffers / silence on watchOS.
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw OpenAITTSError.badStatus(status, String(message.prefix(180)))
        }
        guard !data.isEmpty else { throw OpenAITTSError.emptyAudio }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-tts-\(UUID().uuidString)")
            .appendingPathExtension("mp3")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func saveKey(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func readKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published var pairing: PairingPayload?
    @Published var snapshot = StateSnapshot(state: .idle, detail: "Not connected")
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var needsPairing = true
    @Published var speechLanguage: SpeechLanguage = .system
    @Published var openAIVoice: OpenAIVoice = OpenAITTS.voice
    @Published var hasOpenAIKey: Bool = OpenAITTS.hasAPIKey

    let client = VibeSignalClient()
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard
    private let pairingKey = "agentpulse.pairing"
    private let speechLanguageKey = "vibesignal.speechLanguage"
    private var watchSpeechTask: SFSpeechRecognitionTask?
    private var lastTTSTimestamp: Int64?
    private var ttsTask: Task<Void, Never>?
    private let backgroundBridge = BackgroundBridge()

    private lazy var phoneSession: PhoneSession = PhoneSession(appModel: self)

    func start() {
        loadPairing()
        loadSpeechLanguage()
        hasOpenAIKey = OpenAITTS.hasAPIKey
        openAIVoice = OpenAITTS.voice
        requestNotificationPermission()
        phoneSession.activate()
        refreshBackgroundBridge()

        client.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                guard let self else { return }
                let prev = self.snapshot.state
                self.snapshot = snap
                // Always synthesize on iPhone (OpenAI if keyed, else Apple voices).
                let phoneTTS = snap.state == .completed
                self.phoneSession.push(
                    state: snap,
                    connected: self.isConnected,
                    ttsPending: phoneTTS
                )
                if prev != snap.state {
                    self.notifyIfNeeded(snap)
                    if snap.state == .completed {
                        self.speakReplyToWatchIfNeeded(snap)
                    }
                }
            }
            .store(in: &cancellables)

        client.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
                if let self {
                    let ttsInFlight =
                        self.snapshot.state == .completed
                        && self.lastTTSTimestamp == self.snapshot.ts
                    self.phoneSession.push(
                        state: self.snapshot,
                        connected: connected,
                        ttsPending: ttsInFlight
                    )
                    self.refreshBackgroundBridge()
                }
            }
            .store(in: &cancellables)

        client.$lastError
            .receive(on: RunLoop.main)
            .assign(to: &$lastError)

        if let pairing {
            connect(pairing)
        }
    }

    /// App became active — heal any socket that died while suspended.
    func handleBecameActive() {
        backgroundBridge.endBackgroundTask()
        refreshBackgroundBridge()
        client.ensureConnected()
    }

    /// Leaving the foreground — extend runtime and keep the audio bridge warm.
    func handleEnteringBackground() {
        backgroundBridge.beginBackgroundExecution()
        refreshBackgroundBridge()
        client.ensureConnected()
    }

    func suspendBackgroundAudioForCapture() {
        backgroundBridge.suspendForCapture()
    }

    func resumeBackgroundAudioAfterCapture() {
        backgroundBridge.resumeAfterCapture()
    }

    private func refreshBackgroundBridge() {
        // Stay runnable whenever we have a pairing — reconnect may take a moment.
        backgroundBridge.setEnabled(pairing != nil)
    }

    func applyPairing(_ payload: PairingPayload) {
        pairing = payload
        needsPairing = false
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: pairingKey)
        }
        connect(payload)
        refreshBackgroundBridge()
    }

    func clearPairing() {
        client.disconnect()
        pairing = nil
        needsPairing = true
        defaults.removeObject(forKey: pairingKey)
        snapshot = StateSnapshot(state: .idle, detail: "Not connected")
        refreshBackgroundBridge()
    }

    func send(_ command: AgentCommand, text: String? = nil) {
        guard isCommandWindowOpen(for: command) else {
            lastError = "This Codex response is no longer accepting remote commands. Start a new turn on your desktop."
            return
        }
        lastError = nil
        client.send(command: command, text: text)
    }

    func handleWatchCommand(_ command: AgentCommand, text: String?) {
        send(command, text: text)
    }

    func handleWatchRecording(at url: URL) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.failWatchSpeech("Speech permission is required on iPhone")
                    try? FileManager.default.removeItem(at: url)
                    return
                }

                let systemLocale = Locale.current.identifier
                    .replacingOccurrences(of: "_", with: "-")
                let locales = [
                    Locale(identifier: self.speechLanguage.localeIdentifier),
                    Locale(identifier: systemLocale),
                    Locale(identifier: "en-US")
                ]
                guard let recognizer = locales
                    .compactMap({ SFSpeechRecognizer(locale: $0) })
                    .first(where: \.isAvailable) else {
                    self.failWatchSpeech("Speech recognition unavailable")
                    try? FileManager.default.removeItem(at: url)
                    return
                }

                self.watchSpeechTask?.cancel()
                let request = SFSpeechURLRecognitionRequest(url: url)
                request.shouldReportPartialResults = false
                request.taskHint = .dictation
                self.watchSpeechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    guard let self else { return }
                    if let error {
                        self.failWatchSpeech(error.localizedDescription)
                        try? FileManager.default.removeItem(at: url)
                        self.watchSpeechTask = nil
                        return
                    }
                    guard let result, result.isFinal else { return }
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    try? FileManager.default.removeItem(at: url)
                    self.watchSpeechTask = nil
                    guard !text.isEmpty else {
                        self.failWatchSpeech("Couldn't hear that — hold and speak again")
                        return
                    }
                    self.send(.voice_prompt, text: text)
                }
            }
        }
    }

    private func failWatchSpeech(_ message: String) {
        lastError = message
        phoneSession.notifyWatchSpeechError(message)
    }

    private func connect(_ payload: PairingPayload) {
        needsPairing = false
        client.connect(pairing: payload)
    }

    private func loadPairing() {
        guard let data = defaults.data(forKey: pairingKey),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            needsPairing = true
            return
        }
        pairing = payload
        needsPairing = false
    }

    private func loadSpeechLanguage() {
        guard let raw = defaults.string(forKey: speechLanguageKey),
              let language = SpeechLanguage(rawValue: raw) else { return }
        speechLanguage = language
    }

    func setSpeechLanguage(_ language: SpeechLanguage) {
        speechLanguage = language
        defaults.set(language.rawValue, forKey: speechLanguageKey)
    }

    func setOpenAIAPIKey(_ key: String) {
        OpenAITTS.apiKey = key
        hasOpenAIKey = OpenAITTS.hasAPIKey
    }

    func clearOpenAIAPIKey() {
        OpenAITTS.apiKey = nil
        hasOpenAIKey = false
    }

    func setOpenAIVoice(_ voice: OpenAIVoice) {
        OpenAITTS.voice = voice
        openAIVoice = voice
    }

    /// Generate TTS on the phone (OpenAI if available, else Apple neural) and ship to Watch.
    private func speakReplyToWatchIfNeeded(_ snap: StateSnapshot) {
        guard snap.state == .completed else { return }
        guard lastTTSTimestamp != snap.ts else { return }
        lastTTSTimestamp = snap.ts

        let text = snap.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let skip = ["Done", "Turn completed", "Waiting for agent", "Listening for agent", "Stopped from Watch"]
        guard !text.isEmpty, !skip.contains(text) else { return }
        if text.hasPrefix("Stopped") { return }

        ttsTask?.cancel()
        let ts = snap.ts
        let language = speechLanguage.localeIdentifier
        ttsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fileURL: URL
                if OpenAITTS.hasAPIKey {
                    do {
                        fileURL = try await OpenAITTS.synthesizeToFile(text)
                    } catch {
                        // Quota / network / billing — fall back to on-device Apple voice.
                        await MainActor.run {
                            self.lastError = error.localizedDescription
                        }
                        fileURL = try await AppleOnDeviceTTS.synthesizeToFile(
                            text,
                            languageCode: language
                        )
                    }
                } else {
                    fileURL = try await AppleOnDeviceTTS.synthesizeToFile(
                        text,
                        languageCode: language
                    )
                }
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                await MainActor.run {
                    // Clear transient OpenAI quota noise once Apple TTS succeeded.
                    if self.lastError?.contains("quota") == true
                        || self.lastError?.contains("OpenAI TTS") == true {
                        self.lastError = nil
                    }
                    self.phoneSession.transferSpeakReply(fileURL: fileURL, stateTs: ts)
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.phoneSession.notifyWatchSpeechError(
                        "Phone TTS failed — using Watch voice"
                    )
                    self.phoneSession.push(
                        state: self.snapshot,
                        connected: self.isConnected,
                        ttsPending: false
                    )
                }
            }
        }
    }

    private func isCommandWindowOpen(for command: AgentCommand) -> Bool {
        let ageMs = Int64(Date().timeIntervalSince1970 * 1_000) - snapshot.ts
        switch command {
        case .approve, .deny:
            return snapshot.state == .waiting && ageMs < 115_000
        case .continue, .retry:
            return snapshot.state == .completed && ageMs < 295_000
        case .stop:
            return isConnected && (snapshot.state == .working || snapshot.state == .waiting)
        case .voice_prompt:
            // One thread only: inject into a paused turn, or start when idle.
            guard isConnected else { return false }
            switch snapshot.state {
            case .idle, .completed, .error:
                return true
            case .working, .waiting:
                return false
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifyIfNeeded(_ snap: StateSnapshot) {
        guard snap.state == .waiting || snap.state == .completed || snap.state == .error else { return }
        let content = UNMutableNotificationContent()
        content.title = "Vibe Signal · \(snap.state.title)"
        content.body = snap.detail
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "agentpulse-\(snap.ts)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
