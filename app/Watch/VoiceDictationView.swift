import SwiftUI
import WatchKit

struct VoiceDictationView: View {
    var onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Voice prompt")
                    .font(.headline)
                Text(text.isEmpty ? "Tap Dictate" : text)
                    .font(.caption2)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Dictate") {
                    presentDictation()
                }
                .buttonStyle(.borderedProminent)
                Button("Send") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onText(trimmed)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { dismiss() }
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            // Auto-open dictation once the sheet appears for faster watch UX.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                presentDictation()
            }
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
                }
            }
        }
    }
}
