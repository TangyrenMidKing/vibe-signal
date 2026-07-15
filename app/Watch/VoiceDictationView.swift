import SwiftUI
import WatchKit

struct VoiceDictationView: View {
    var onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var holding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(holding ? "Listening…" : "Hold mic, release to send")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PulseTheme.mist)
                    .multilineTextAlignment(.center)

                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(holding ? PulseTheme.signal(.working) : PulseTheme.accent)
                    .scaleEffect(holding ? 1.12 : 1)
                    .animation(.easeOut(duration: 0.15), value: holding)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !holding else { return }
                                holding = true
                                WKInterfaceDevice.current().play(.start)
                                presentDictation()
                            }
                            .onEnded { _ in
                                holding = false
                                WKInterfaceDevice.current().play(.click)
                            }
                    )

                if !text.isEmpty {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Send") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onText(trimmed)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel", role: .cancel) { dismiss() }
            }
            .padding(.horizontal, 4)
        }
    }

    private func presentDictation() {
        guard let controller = WKExtension.shared().visibleInterfaceController else {
            return
        }
        controller.presentTextInputController(
            withSuggestions: ["Continue.", "Retry.", "Explain.", "Add unit tests."],
            allowedInputMode: .plain
        ) { results in
            DispatchQueue.main.async {
                if let spoken = results?.first as? String {
                    text = spoken
                    let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onText(trimmed)
                    }
                }
                holding = false
            }
        }
    }
}
