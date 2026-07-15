import Foundation
import SwiftUI

public enum AgentState: String, Codable, Sendable, CaseIterable {
    case idle
    case working
    case waiting
    case completed
    case error

    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .completed: return "Completed"
        case .error: return "Error"
        }
    }
}

public enum AgentCommand: String, Codable, Sendable {
    case approve
    case deny
    case `continue`
    case retry
    case voice_prompt
}

public struct StateSnapshot: Codable, Equatable, Sendable {
    public var type: String
    public var state: AgentState
    public var detail: String
    public var sessionId: String?
    public var turnId: String?
    public var project: String?
    public var repo: String?
    public var cwd: String?
    public var ts: Int64

    public init(
        type: String = "state",
        state: AgentState,
        detail: String,
        sessionId: String? = nil,
        turnId: String? = nil,
        project: String? = nil,
        repo: String? = nil,
        cwd: String? = nil,
        ts: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.type = type
        self.state = state
        self.detail = detail
        self.sessionId = sessionId
        self.turnId = turnId
        self.project = project
        self.repo = repo
        self.cwd = cwd
        self.ts = ts
    }
}

public struct CommandMessage: Codable, Sendable {
    public var type: String = "command"
    public var command: AgentCommand
    public var text: String?
    public var id: String?

    public init(command: AgentCommand, text: String? = nil, id: String? = nil) {
        self.command = command
        self.text = text
        self.id = id
    }
}

public struct PairingPayload: Codable, Equatable, Sendable {
    public var v: Int
    public var name: String
    public var host: String
    public var port: Int
    public var token: String

    public var wsURL: URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }
}

public enum WireMessage: Equatable {
    case state(StateSnapshot)
    case ping(Int64)
    case ack(command: String, ok: Bool, message: String?)
    case unknown

    public static func parse(_ data: Data) -> WireMessage {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return .unknown
        }
        switch type {
        case "state":
            if let decoded = try? JSONDecoder().decode(StateSnapshot.self, from: data) {
                return .state(decoded)
            }
            return .unknown
        case "ping":
            let ts = (obj["ts"] as? NSNumber)?.int64Value ?? 0
            return .ping(ts)
        case "ack":
            let command = obj["command"] as? String ?? ""
            let ok = obj["ok"] as? Bool ?? false
            let message = obj["message"] as? String
            return .ack(command: command, ok: ok, message: message)
        default:
            return .unknown
        }
    }
}

/// Visual language for Vibe Signal: ink canvas + luminous signal states.
/// Lives in Models.swift so both iOS and Watch targets always see it
/// (even when an older Xcode project never added Shared/Theme.swift).
enum PulseTheme {
    static let ink = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let inkElevated = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let mist = Color.white.opacity(0.72)
    static let mistSoft = Color.white.opacity(0.45)
    static let line = Color.white.opacity(0.10)
    static let accent = Color(red: 0.45, green: 0.82, blue: 0.95)

    static func signal(_ state: AgentState) -> Color {
        switch state {
        case .idle: return Color(red: 0.55, green: 0.58, blue: 0.62)
        case .working: return Color(red: 0.95, green: 0.28, blue: 0.32)
        case .waiting: return Color(red: 0.98, green: 0.78, blue: 0.22)
        case .completed: return Color(red: 0.30, green: 0.86, blue: 0.52)
        case .error: return Color(red: 0.98, green: 0.52, blue: 0.22)
        }
    }

    static func signalSoft(_ state: AgentState) -> Color {
        signal(state).opacity(0.22)
    }
}

extension AgentState {
    var pulseLabel: String {
        switch self {
        case .idle: return "Standing by"
        case .working: return "Agent working"
        case .waiting: return "Needs you"
        case .completed: return "Done"
        case .error: return "Error"
        }
    }
}
