import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPairing = false
    @State private var showManual = false
    @State private var appear = false

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                SignalHero(snapshot: model.snapshot, connected: model.isConnected)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                    .animation(.easeOut(duration: 0.45), value: appear)

                Spacer(minLength: 16)

                contextActions
                    .padding(.horizontal, 20)

                HoldToTalkButton { text in
                    model.send(.voice_prompt, text: text)
                }
                .padding(.top, 28)
                .padding(.bottom, 8)

                if let err = model.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
            }
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
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
        .onAppear {
            appear = true
            if model.needsPairing {
                showPairing = true
            }
        }
    }

    private var background: some View {
        LiquidAmbientBackground(state: model.snapshot.state)
            .animation(.easeInOut(duration: 0.55), value: model.snapshot.state)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vibe Signal")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.02)
                    .foregroundStyle(.white)
                Text(model.isConnected ? "Linked to desktop" : "Not linked")
                    .font(.caption)
                    .foregroundStyle(PulseTheme.mistSoft)
            }
            Spacer()
            Menu {
                Button("Scan QR", systemImage: "qrcode.viewfinder") { showPairing = true }
                Button("Enter Manually", systemImage: "keyboard") { showManual = true }
                if model.pairing != nil {
                    Divider()
                    Button("Disconnect", systemImage: "link.badge.minus", role: .destructive) {
                        model.clearPairing()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(PulseTheme.mist)
            }
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        switch model.snapshot.state {
        case .waiting:
            HStack(spacing: 12) {
                PulseActionButton(title: "Approve", tint: PulseTheme.signal(.completed)) {
                    model.send(.approve)
                }
                PulseActionButton(title: "Deny", tint: PulseTheme.signal(.working), outlined: true) {
                    model.send(.deny)
                }
            }
        case .completed, .error:
            HStack(spacing: 12) {
                PulseActionButton(title: "Continue", tint: PulseTheme.accent) {
                    model.send(.continue)
                }
                PulseActionButton(title: "Retry", tint: PulseTheme.signal(.error), outlined: true) {
                    model.send(.retry)
                }
            }
        default:
            EmptyView()
        }
    }
}

struct SignalHero: View {
    let snapshot: StateSnapshot
    let connected: Bool

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(PulseTheme.signal(snapshot.state).opacity(0.22), lineWidth: 16)
                    .frame(width: 172, height: 172)
                    .blur(radius: 0.5)
                LiquidSignalOrb(state: snapshot.state, size: 132)
            }

            VStack(spacing: 8) {
                Text(snapshot.state.pulseLabel.uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(PulseTheme.signal(snapshot.state))

                Text(snapshot.state.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.03)
                    .foregroundStyle(.white)

                ProjectRepoChips(project: snapshot.project, repo: snapshot.repo)

                Text(snapshot.detail)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(PulseTheme.mist)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Circle()
                        .fill(connected ? PulseTheme.signal(.completed) : PulseTheme.signal(.idle))
                        .frame(width: 7, height: 7)
                    Text(connected ? "Live" : "Reconnect from menu")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PulseTheme.mistSoft)
                }
                .padding(.top, 4)
            }
        }
    }
}

struct ProjectRepoChips: View {
    var project: String?
    var repo: String?

    var body: some View {
        if project != nil || repo != nil {
            VStack(spacing: 6) {
                if let project, !project.isEmpty {
                    chip(icon: "folder.fill", text: project)
                }
                if let repo, !repo.isEmpty, repo != project {
                    chip(icon: "shippingbox.fill", text: repo)
                }
            }
            .padding(.top, 2)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(PulseTheme.mist)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(PulseTheme.inkElevated.opacity(0.9), in: Capsule())
        .overlay(Capsule().stroke(PulseTheme.line, lineWidth: 1))
    }
}

struct PulseActionButton: View {
    let title: String
    var tint: Color
    var outlined: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(outlined ? tint : Color.white)
                .background(
                    Group {
                        if outlined {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(tint.opacity(0.55), lineWidth: 1.2)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(PulseTheme.inkElevated)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(tint)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}
