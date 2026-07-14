import Foundation
import Combine
import UserNotifications
import WatchConnectivity

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published var pairing: PairingPayload?
    @Published var snapshot = StateSnapshot(state: .idle, detail: "Not connected")
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var needsPairing = true

    let client = AgentPulseClient()
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard
    private let pairingKey = "agentpulse.pairing"

    private lazy var phoneSession: PhoneSession = PhoneSession(appModel: self)

    func start() {
        loadPairing()
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

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifyIfNeeded(_ snap: StateSnapshot) {
        guard snap.state == .waiting || snap.state == .completed || snap.state == .error else { return }
        let content = UNMutableNotificationContent()
        content.title = "AgentPulse · \(snap.state.title)"
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
