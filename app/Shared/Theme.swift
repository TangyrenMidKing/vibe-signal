import SwiftUI

/// Visual language for Vibe Signal: ink canvas + luminous signal states.
enum PulseTheme {
    static let ink = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let inkElevated = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let mist = Color.white.opacity(0.72)
    static let mistSoft = Color.white.opacity(0.45)
    static let line = Color.white.opacity(0.10)
    static let accent = Color(red: 0.45, green: 0.82, blue: 0.95) // link blue from brand mark

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
