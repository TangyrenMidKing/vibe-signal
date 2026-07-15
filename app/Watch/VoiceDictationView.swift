import SwiftUI
import WatchKit

/// Hold-to-talk on Watch uses system dictation (Speech framework is not available on watchOS).
struct VoiceDictationView: View {
    var onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var holding = false
    @State private var cancelled = false
    @State private var presented = false

    var body: some View {
        VStack(spacing: 10) {
            Text(statusCopy)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PulseTheme.mist)
                .multilineTextAlignment(.center)

            Image(systemName: cancelled ? "xmark.circle.fill" : "mic.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    cancelled
                        ? PulseTheme.signal(.error)
                        : holding ? PulseTheme.signal(.working) : PulseTheme.accent
                )
                .scaleEffect(holding ? 1.12 : 1)
                .animation(.easeOut(duration: 0.15), value: holding)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !holding { beginHold() }
                            if value.translation.width < -40, !cancelled {
                                cancelHold()
                            }
                        }
                        .onEnded { _ in
                            if !cancelled { endHold() }
                        }
                )
                .accessibilityLabel("Hold to talk")
                .accessibilityHint("Slide left before releasing to cancel")

            if !text.isEmpty {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }

            Button("Cancel", role: .cancel) { dismiss() }
        }
        .padding(.horizontal, 4)
    }

    private var statusCopy: String {
        if cancelled { return "Cancelled" }
        if holding || presented { return "Listening — slide left to cancel" }
        return "Hold to talk"
    }

    private func beginHold() {
        cancelled = false
        text = ""
        holding = true
        WKInterfaceDevice.current().play(.start)
        presentDictation()
    }

    private func cancelHold() {
        cancelled = true
        holding = false
        presented = false
        text = ""
        WKInterfaceDevice.current().play(.failure)
    }

    private func endHold() {
        guard holding else { return }
        holding = false
        WKInterfaceDevice.current().play(.click)
        // Dictation result arrives asynchronously from presentTextInputController.
    }

    private func presentDictation() {
        guard !presented else { return }
        presented = true
        guard let controller = WKExtension.shared().visibleInterfaceController else {
            presented = false
            holding = false
            return
        }
        controller.presentTextInputController(
            withSuggestions: ["Continue.", "Retry.", "Explain.", "Add unit tests."],
            allowedInputMode: .plain
        ) { results in
            DispatchQueue.main.async {
                presented = false
                holding = false
                if cancelled {
                    cancelled = false
                    return
                }
                if let spoken = results?.first as? String {
                    text = spoken
                    let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onText(trimmed)
                        dismiss()
                    }
                }
            }
        }
    }
}
