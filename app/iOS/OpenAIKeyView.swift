import SwiftUI

struct OpenAIKeyView: View {
    var hasKey: Bool
    var onSave: (String) -> Void
    var onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("OpenAI API Key")
                } footer: {
                    Text(
                        "Used on iPhone to synthesize high-quality reply audio (tts-1-hd) for the Watch. Stored in Keychain on this device only."
                    )
                }

                if hasKey {
                    Section {
                        Label("A key is already saved", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Remove key", role: .destructive) {
                            onClear()
                        }
                    }
                }
            }
            .navigationTitle("Watch TTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(key)
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
