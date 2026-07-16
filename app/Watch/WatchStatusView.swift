import SwiftUI

struct WatchStatusView: View {
    @EnvironmentObject private var model: WatchModel
    @State private var showingVoice = false

    private var disconnected: Bool {
        !model.phoneReachable && model.snapshot.state == .idle
    }

    private var state: AgentState {
        disconnected ? .idle : model.snapshot.state
    }

    private var signal: Color {
        PulseTheme.signal(state)
    }

    private var headline: String {
        disconnected ? "Offline" : state.title
    }

    private var detail: String {
        disconnected ? "Open Vibe Signal on iPhone" : model.snapshot.state.pulseLabel
    }

    var body: some View {
        ZStack {
            PulseTheme.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                statusHeader

                Spacer(minLength: 8)

                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseTheme.mist)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)

                if let project = model.snapshot.project, !project.isEmpty, !disconnected {
                    Text(project)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(PulseTheme.mistSoft)
                        .lineLimit(1)
                        .padding(.top, 5)
                }

                Spacer(minLength: 10)

                if !disconnected {
                    controls
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showingVoice) {
            VoiceDictationView { text in
                model.send(.voice_prompt, text: text)
                showingVoice = false
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(signal)
                .frame(width: 8, height: 8)
                .shadow(color: signal.opacity(0.6), radius: 4)

            Text(headline.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controls: some View {
        switch model.snapshot.state {
        case .waiting:
            HStack(spacing: 7) {
                actionButton("Approve", icon: "checkmark") { model.send(.approve) }
                    .tint(PulseTheme.signal(.completed))
                actionButton("Decline", icon: "xmark") { model.send(.deny) }
                    .tint(PulseTheme.signal(.working))
            }
        case .completed, .error:
            HStack(spacing: 7) {
                actionButton("Continue", icon: "arrow.right") { model.send(.continue) }
                    .tint(PulseTheme.accent)
                speakButton
            }
        default:
            speakButton
        }
    }

    private var speakButton: some View {
        Button {
            showingVoice = true
        } label: {
            Label("Speak", systemImage: "mic.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(PulseTheme.accent)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Speak")
        .accessibilityHint("Opens dictation to send a prompt")
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }
}
