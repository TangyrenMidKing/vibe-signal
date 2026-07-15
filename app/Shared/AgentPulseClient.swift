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
    /// Bumps on every open/close so late callbacks from cancelled sockets are ignored.
    private var generation = 0
    private var reconnectAttempt = 0

    public var onStateChange: ((StateSnapshot) -> Void)?

    public init() {}

    public func connect(pairing: PairingPayload) {
        self.pairing = pairing
        shouldRun = true
        reconnectAttempt = 0
        reconnectTask?.cancel()
        openSocket()
    }

    public func disconnect() {
        shouldRun = false
        reconnectTask?.cancel()
        reconnectTask = nil
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
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
        guard let pairing, let url = pairing.wsURL else {
            lastError = "Invalid pairing"
            isConnected = false
            return
        }

        generation += 1
        let gen = generation

        let previous = task
        task = nil
        previous?.cancel(with: .goingAway, reason: nil)

        if session == nil {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 30
            session = URLSession(configuration: config)
        }

        let task = session!.webSocketTask(with: url)
        self.task = task
        // Stay "disconnected" in UI until the server sends the initial state
        // (or any frame). Setting true here raced with cancel callbacks.
        task.resume()
        receiveLoop(generation: gen)
    }

    private func receiveLoop(generation gen: Int) {
        guard gen == generation, let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                switch result {
                case .failure(let error):
                    self.handleDisconnect(error: error, generation: gen)
                case .success(let message):
                    if !self.isConnected {
                        self.isConnected = true
                        self.lastError = nil
                        self.reconnectAttempt = 0
                    }
                    self.handle(message)
                    self.receiveLoop(generation: gen)
                }
            }
        }
    }

    private func handleDisconnect(error: Error, generation gen: Int) {
        guard gen == generation else { return }
        isConnected = false
        // Cancellation during intentional reconnect is not a user-facing error.
        let ns = error as NSError
        let cancelled =
            ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
        if !cancelled {
            lastError = error.localizedDescription
        }
        scheduleReconnect()
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
            if ok {
                lastError = nil
            } else {
                lastError = message ?? "Command failed"
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
        reconnectAttempt += 1
        // 1s, 2s, 4s… capped at 8s — avoids slam-reconnect flap.
        let delay = min(8.0, pow(2.0, Double(min(reconnectAttempt, 3)) - 1.0))
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, shouldRun else { return }
            openSocket()
        }
    }
}
