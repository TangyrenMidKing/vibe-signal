import SwiftUI

struct WatchStatusView: View {
    @EnvironmentObject private var model: WatchModel
    @State private var showingVoice = false
    @State private var showingFeedback = false

    private var disconnected: Bool {
        !model.phoneReachable && model.snapshot.state == .idle
    }

    private var signal: Color {
        disconnected ? PulseTheme.signal(.idle) : PulseTheme.signal(model.snapshot.state)
    }

    var body: some View {
        ZStack {
            PulseTheme.ink.ignoresSafeArea()
            RadialGradient(
                colors: [signal.opacity(0.55), PulseTheme.ink.opacity(0.2)],
                center: .center,
                startRadius: 4,
                endRadius: 90
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: model.snapshot.state)

            VStack(spacing: 6) {
                Circle()
                    .fill(signal)
                    .frame(width: 14, height: 14)
                    .shadow(color: signal.opacity(0.7), radius: 6)

                Text(disconnected ? "OFFLINE" : model.snapshot.state.title.uppercased())
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white)

                Text(disconnected ? "Open iPhone" : model.snapshot.detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PulseTheme.mist)
                    .lineLimit(2)

                if !disconnected, !model.snapshot.detail.isEmpty {
                    Button("View response") { showingFeedback = true }
                        .font(.caption2.weight(.semibold))
                        .tint(PulseTheme.accent)
                }

                if !disconnected {
                    if let project = model.snapshot.project, !project.isEmpty {
                        Text(project)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(PulseTheme.accent)
                            .lineLimit(1)
                    }
                    if let repo = model.snapshot.repo,
                       !repo.isEmpty,
                       repo != model.snapshot.project {
                        Text(repo)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(PulseTheme.mistSoft)
                            .lineLimit(1)
                    }
                }

                if !disconnected {
                    controls
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 6)
        }
        .sheet(isPresented: $showingVoice) {
            VoiceDictationView { text in
                model.send(.voice_prompt, text: text)
                showingVoice = false
            }
        }
        .sheet(isPresented: $showingFeedback) {
            FeedbackLogView(text: model.snapshot.detail)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.snapshot.state {
        case .waiting:
            HStack(spacing: 6) {
                Button("OK") { model.send(.approve) }
                    .tint(PulseTheme.signal(.completed))
                Button("No") { model.send(.deny) }
                    .tint(PulseTheme.signal(.working))
            }
            .font(.caption2.weight(.semibold))
        case .completed, .error:
            HStack(spacing: 6) {
                Button("Go") { model.send(.continue) }
                    .tint(PulseTheme.accent)
                Button("Mic") { showingVoice = true }
            }
            .font(.caption2.weight(.semibold))
        default:
            Button {
                showingVoice = true
            } label: {
                Image(systemName: "mic.fill")
            }
            .tint(PulseTheme.accent)
            .font(.caption)
        }
    }
}
