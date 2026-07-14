import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPairing = false
    @State private var showManual = false
    @State private var showVoice = false

    var body: some View {
        NavigationStack {
            ZStack {
                model.snapshot.state.color.opacity(0.18).ignoresSafeArea()
                VStack(spacing: 24) {
                    StatusCard(snapshot: model.snapshot, connected: model.isConnected)
                    ActionBar(
                        state: model.snapshot.state,
                        onApprove: { model.send(.approve) },
                        onDeny: { model.send(.deny) },
                        onContinue: { model.send(.continue) },
                        onRetry: { model.send(.retry) },
                        onVoice: { showVoice = true }
                    )
                    if let err = model.lastError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("AgentPulse")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Scan QR") { showPairing = true }
                        Button("Enter Manually") { showManual = true }
                        if model.pairing != nil {
                            Button("Disconnect", role: .destructive) { model.clearPairing() }
                        }
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showPairing) {
                QRScannerView { payload in
                    model.applyPairing(payload)
                    showPairing = false
                }
            }
            .sheet(isPresented: $showManual) {
                ManualPairingView { payload in
                    model.applyPairing(payload)
                    showManual = false
                }
            }
            .sheet(isPresented: $showVoice) {
                VoicePromptView { text in
                    model.send(.voice_prompt, text: text)
                    showVoice = false
                }
            }
            .onAppear {
                if model.needsPairing {
                    showPairing = true
                }
            }
        }
    }
}

struct StatusCard: View {
    let snapshot: StateSnapshot
    let connected: Bool

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(snapshot.state.color)
                .frame(width: 96, height: 96)
                .shadow(color: snapshot.state.color.opacity(0.5), radius: 16)
            Text(snapshot.state.title.uppercased())
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(1.5)
            Text(snapshot.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Circle()
                    .fill(connected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(connected ? "Live" : "Disconnected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct ActionBar: View {
    let state: AgentState
    var onApprove: () -> Void
    var onDeny: () -> Void
    var onContinue: () -> Void
    var onRetry: () -> Void
    var onVoice: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch state {
            case .waiting:
                HStack(spacing: 12) {
                    Button("Approve", action: onApprove)
                        .buttonStyle(PulseButtonStyle(fill: .green))
                    Button("Deny", action: onDeny)
                        .buttonStyle(PulseButtonStyle(fill: .red))
                }
            case .completed, .error:
                HStack(spacing: 12) {
                    Button("Continue", action: onContinue)
                        .buttonStyle(PulseButtonStyle(fill: .blue))
                    Button("Retry", action: onRetry)
                        .buttonStyle(PulseButtonStyle(fill: .orange))
                }
            default:
                EmptyView()
            }
            Button {
                onVoice()
            } label: {
                Label("Voice", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PulseButtonStyle(fill: .primary.opacity(0.85)))
        }
    }
}

struct PulseButtonStyle: ButtonStyle {
    var fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
