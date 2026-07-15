import SwiftUI

/// Liquid signal core — morphing luminous mass clipped to a sphere.
/// Motion slows / freezes when Reduce Motion is on.
struct LiquidSignalOrb: View {
    var state: AgentState
    var size: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { PulseTheme.signal(state) }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0.0 : t
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .blur(radius: size * 0.18)
                    .frame(width: size * 1.35, height: size * 1.35)
                    .scaleEffect(reduceMotion ? 1.0 : 1.0 + 0.03 * sin(phase * 1.4))

                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))

                    liquidMass(phase: phase)
                        .blur(radius: size * 0.055)

                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(state == .idle ? 0.18 : 0.42),
                                    .white.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.38
                            )
                        )
                        .frame(width: size * 0.55, height: size * 0.32)
                        .offset(
                            x: reduceMotion ? -size * 0.12 : size * 0.14 * cos(phase * 0.9),
                            y: reduceMotion ? -size * 0.22 : -size * 0.22 + size * 0.06 * sin(phase * 1.1)
                        )
                        .blendMode(.screen)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.35)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )

                    if state == .working && !reduceMotion {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white.opacity(0.9))
                            .scaleEffect(1.15)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.45),
                                    .white.opacity(0.08),
                                    tint.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: tint.opacity(0.55), radius: size * 0.18, y: size * 0.06)
            }
            .animation(.easeInOut(duration: 0.5), value: state)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func liquidMass(phase: Double) -> some View {
        let amplitude = energy(for: state)
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.95),
                            tint.opacity(0.65),
                            tint.opacity(0.35)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: size * 0.05,
                        endRadius: size * 0.55
                    )
                )

            ForEach(0..<4, id: \.self) { i in
                let speed = 0.7 + Double(i) * 0.35
                let angle = phase * speed + Double(i) * 1.7
                let r = size * (0.12 + 0.04 * Double(i % 2)) * amplitude
                Ellipse()
                    .fill(blobColor(index: i).opacity(0.55))
                    .frame(
                        width: size * (0.42 + 0.08 * sin(angle)),
                        height: size * (0.36 + 0.1 * cos(angle * 1.3))
                    )
                    .offset(
                        x: r * cos(angle),
                        y: r * sin(angle * 0.85)
                    )
                    .blendMode(.plusLighter)
            }
        }
    }

    private func energy(for state: AgentState) -> CGFloat {
        switch state {
        case .idle: return 0.35
        case .working: return 1.0
        case .waiting: return 0.75
        case .completed: return 0.45
        case .error: return 0.9
        }
    }

    private func blobColor(index: Int) -> Color {
        switch index % 4 {
        case 0: return .white
        case 1: return tint
        case 2: return PulseTheme.accent
        default: return Color(red: 1, green: 0.92, blue: 0.75)
        }
    }
}

/// Subtle ink caustic wash behind the hero — not a glass card.
struct LiquidAmbientBackground: View {
    var state: AgentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 2.0 : 1.0 / 24.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            let tint = PulseTheme.signal(state)
            ZStack {
                PulseTheme.ink
                Circle()
                    .fill(tint.opacity(0.28))
                    .frame(width: 340, height: 340)
                    .blur(radius: 60)
                    .offset(
                        x: reduceMotion ? 0 : 18 * cos(t * 0.35),
                        y: reduceMotion ? -40 : -40 + 16 * sin(t * 0.28)
                    )
                Circle()
                    .fill(PulseTheme.accent.opacity(0.12))
                    .frame(width: 260, height: 260)
                    .blur(radius: 50)
                    .offset(
                        x: reduceMotion ? 60 : 60 + 22 * sin(t * 0.31),
                        y: reduceMotion ? 80 : 80 + 14 * cos(t * 0.4)
                    )
            }
        }
    }
}
