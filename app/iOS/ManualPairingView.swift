import SwiftUI

struct ManualPairingView: View {
    var onPayload: (PairingPayload) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var port = "8787"
    @State private var token = ""
    @State private var jsonPaste = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Host (LAN IP)", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.decimalPad)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Or paste pairing JSON") {
                    TextField("JSON", text: $jsonPaste, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(.footnote, design: .monospaced))
                    Button("Parse JSON") {
                        parseJSON()
                    }
                }
            }
            .navigationTitle("Manual Pairing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { submit() }
                        .disabled(host.isEmpty || token.isEmpty || Int(port) == nil)
                }
            }
        }
    }

    private func parseJSON() {
        guard let data = jsonPaste.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else { return }
        host = payload.host
        port = String(payload.port)
        token = payload.token
    }

    private func submit() {
        guard let p = Int(port) else { return }
        onPayload(PairingPayload(v: 1, name: "AgentPulse", host: host, port: p, token: token))
    }
}
