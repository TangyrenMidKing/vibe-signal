import Foundation
import Combine

/// Minimal WebSocket client with auto-reconnect for the Vibe Signal LAN protocol.
@MainActor
public final class VibeSignalClient: ObservableObject {
    @Published public private(set) var snapshot = StateSnapshot(state: .idle, detail: "Not connected")
    @Published public private(set) var isConnected = false
    @Published public private(set) var lastError: String?

    private var pairing: PairingPayload?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var shouldRun = false
    private var pingHandler: (() -> Void)?

    public var onStateChange: ((StateSnapshot) -> Void)?

    public init() {}

    public func connect(pairing: PairingPayload) {
        self.pairing = pairing
        shouldRun = true
        reconnectTask?.cancel()
        openSocket()
    }

    public func disconnect() {
        shouldRun = false
        reconnectTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    public func send(command: AgentCommand, text: String? = nil) {
        let msg = CommandMessage(command: command, text: text, id: UUID().uuidString)
        guard let data = try? JSONEncoder().encode(msg),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    private func openSocket() {
        task?.cancel(with: .goingAway, reason: nil)
        guard let pairing, let url = pairing.wsURL else {
            lastError = "Invalid pairing"
            return
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        isConnected = true
        lastError = nil
        receiveLoop()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.scheduleReconnect()
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let s):
            data = Data(s.utf8)
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        switch WireMessage.parse(data) {
        case .state(let snap):
            snapshot = snap
            onStateChange?(snap)
        case .ping:
            task?.send(.string(#"{"type":"pong"}"#)) { _ in }
        case .ack(_, let ok, let message):
            if !ok {
                lastError = message ?? "Command failed"
                // The connector has already closed its hook window. Do not
                // leave stale Continue/Retry controls on screen.
                if message?.localizedCaseInsensitiveContains("not waiting") == true {
                    let idle = StateSnapshot(state: .idle, detail: "Waiting for agent")
                    snapshot = idle
                    onStateChange?(idle)
                }
            }
        case .unknown:
            break
        }
    }

    private func scheduleReconnect() {
        guard shouldRun else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, shouldRun else { return }
            openSocket()
        }
    }
}
