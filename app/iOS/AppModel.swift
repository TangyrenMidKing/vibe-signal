import Foundation
import Combine
import UserNotifications
import WatchConnectivity

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
        self == .system ? Locale.current.identifier : rawValue
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

    let client = VibeSignalClient()
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard
    private let pairingKey = "agentpulse.pairing"
    private let speechLanguageKey = "vibesignal.speechLanguage"

    private lazy var phoneSession: PhoneSession = PhoneSession(appModel: self)

    func start() {
        loadPairing()
        loadSpeechLanguage()
        requestNotificationPermission()
        phoneSession.activate()

        client.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                guard let self else { return }
                let prev = self.snapshot.state
                self.snapshot = snap
                self.phoneSession.push(state: snap, connected: self.isConnected)
                if prev != snap.state {
                    self.notifyIfNeeded(snap)
                }
            }
            .store(in: &cancellables)

        client.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
                if let self {
                    self.phoneSession.push(state: self.snapshot, connected: connected)
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

    func applyPairing(_ payload: PairingPayload) {
        pairing = payload
        needsPairing = false
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: pairingKey)
        }
        connect(payload)
    }

    func clearPairing() {
        client.disconnect()
        pairing = nil
        needsPairing = true
        defaults.removeObject(forKey: pairingKey)
        snapshot = StateSnapshot(state: .idle, detail: "Not connected")
    }

    func send(_ command: AgentCommand, text: String? = nil) {
        client.send(command: command, text: text)
    }

    func handleWatchCommand(_ command: AgentCommand, text: String?) {
        send(command, text: text)
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
