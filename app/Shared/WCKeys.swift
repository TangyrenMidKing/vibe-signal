import Foundation

/// Keys shared between iPhone and Watch over WatchConnectivity.
public enum WCKeys {
    public static let state = "state"
    public static let detail = "detail"
    public static let ts = "ts"
    public static let sessionId = "sessionId"
    public static let turnId = "turnId"
    public static let connected = "connected"
    public static let command = "command"
    public static let text = "text"
}

public extension StateSnapshot {
    var wcPayload: [String: Any] {
        var dict: [String: Any] = [
            WCKeys.state: state.rawValue,
            WCKeys.detail: detail,
            WCKeys.ts: ts
        ]
        if let sessionId { dict[WCKeys.sessionId] = sessionId }
        if let turnId { dict[WCKeys.turnId] = turnId }
        return dict
    }

    static func fromWC(_ dict: [String: Any]) -> StateSnapshot? {
        guard let raw = dict[WCKeys.state] as? String,
              let state = AgentState(rawValue: raw) else { return nil }
        let detail = dict[WCKeys.detail] as? String ?? ""
        let ts = (dict[WCKeys.ts] as? NSNumber)?.int64Value
            ?? Int64(Date().timeIntervalSince1970 * 1000)
        return StateSnapshot(
            state: state,
            detail: detail,
            sessionId: dict[WCKeys.sessionId] as? String,
            turnId: dict[WCKeys.turnId] as? String,
            ts: ts
        )
    }
}
