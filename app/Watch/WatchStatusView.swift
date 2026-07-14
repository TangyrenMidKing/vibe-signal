import SwiftUI

struct WatchStatusView: View {
    @EnvironmentObject private var model: WatchModel
    @State private var showingVoice = false

    private var disconnected: Bool {
        !model.phoneReachable && model.snapshot.state == .idle
    }

    var body: some View {
        ZStack {
            (disconnected ? Color.gray : model.snapshot.state.color)
                .opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text(disconnected ? "OFFLINE" : model.snapshot.state.title.uppercased())
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(1)

                Text(disconnected ? "Open iPhone app" : model.snapshot.detail)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(3)

                if !disconnected {
                    controls
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
    }

    @ViewBuilder
    private var controls: some View {
        switch model.snapshot.state {
        case .waiting:
            HStack(spacing: 6) {
                Button("OK") { model.send(.approve) }
                    .tint(.green)
                Button("No") { model.send(.deny) }
                    .tint(.red)
            }
            .font(.caption2)
        case .completed, .error:
            HStack(spacing: 6) {
                Button("Go") { model.send(.continue) }
                    .tint(.blue)
                Button("Mic") { showingVoice = true }
            }
            .font(.caption2)
        default:
            Button {
                showingVoice = true
            } label: {
                Image(systemName: "mic.fill")
            }
            .font(.caption)
        }
    }
}
