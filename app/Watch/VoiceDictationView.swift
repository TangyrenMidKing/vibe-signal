import SwiftUI

/// Watch voice/text prompt entry.
///
/// Uses a focused `TextField` so watchOS opens its system input UI
/// (scribble + dictation mic). Custom AVAudioRecorder + LongPressGesture was
/// unreliable on watchOS (non-Button gestures often never fire).
struct VoiceDictationView: View {
    var onText: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text("Speak or type a prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PulseTheme.mist)
                .multilineTextAlignment(.center)

            TextField("Prompt", text: $text)
                .focused($fieldFocused)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit(sendIfPossible)

            Button("Send") { sendIfPossible() }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(trimmed.isEmpty)

            Button("Cancel", role: .cancel) { dismiss() }
                .font(.caption2)
        }
        .padding(.horizontal, 4)
        .onAppear { fieldFocused = true }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendIfPossible() {
        let value = trimmed
        guard !value.isEmpty else { return }
        onText(value)
        dismiss()
    }
}
