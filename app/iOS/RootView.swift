import SwiftUI
import Speech
import AVFoundation
import UIKit
import Combine

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

// MARK: - Liquid signal (kept in RootView so AgentPulse.xcodeproj picks them up)

struct LiquidSignalOrb: View {
    var state: AgentState
    var size: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { PulseTheme.signal(state) }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0.0 : t
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .blur(radius: size * 0.18)
                    .frame(width: size * 1.35, height: size * 1.35)
                    .scaleEffect(reduceMotion ? 1.0 : 1.0 + 0.03 * sin(phase * 1.4))

                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))

                    liquidMass(phase: phase)
                        .blur(radius: size * 0.055)

                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(state == .idle ? 0.18 : 0.42),
                                    .white.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.38
                            )
                        )
                        .frame(width: size * 0.55, height: size * 0.32)
                        .offset(
                            x: reduceMotion ? -size * 0.12 : size * 0.14 * cos(phase * 0.9),
                            y: reduceMotion ? -size * 0.22 : -size * 0.22 + size * 0.06 * sin(phase * 1.1)
                        )
                        .blendMode(.screen)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.35)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )

                    if state == .working && !reduceMotion {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white.opacity(0.9))
                            .scaleEffect(1.15)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.45),
                                    .white.opacity(0.08),
                                    tint.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: tint.opacity(0.55), radius: size * 0.18, y: size * 0.06)
            }
            .animation(.easeInOut(duration: 0.5), value: state)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func liquidMass(phase: Double) -> some View {
        let amplitude = energy(for: state)
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.95),
                            tint.opacity(0.65),
                            tint.opacity(0.35)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: size * 0.05,
                        endRadius: size * 0.55
                    )
                )

            ForEach(0..<4, id: \.self) { i in
                let speed = 0.7 + Double(i) * 0.35
                let angle = phase * speed + Double(i) * 1.7
                let r = size * (0.12 + 0.04 * Double(i % 2)) * amplitude
                Ellipse()
                    .fill(blobColor(index: i).opacity(0.55))
                    .frame(
                        width: size * (0.42 + 0.08 * sin(angle)),
                        height: size * (0.36 + 0.1 * cos(angle * 1.3))
                    )
                    .offset(
                        x: r * cos(angle),
                        y: r * sin(angle * 0.85)
                    )
                    .blendMode(.plusLighter)
            }
        }
    }

    private func energy(for state: AgentState) -> CGFloat {
        switch state {
        case .idle: return 0.35
        case .working: return 1.0
        case .waiting: return 0.75
        case .completed: return 0.45
        case .error: return 0.9
        }
    }

    private func blobColor(index: Int) -> Color {
        switch index % 4 {
        case 0: return .white
        case 1: return tint
        case 2: return PulseTheme.accent
        default: return Color(red: 1, green: 0.92, blue: 0.75)
        }
    }
}

struct LiquidAmbientBackground: View {
    var state: AgentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 2.0 : 1.0 / 24.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            let tint = PulseTheme.signal(state)
            ZStack {
                PulseTheme.ink
                Circle()
                    .fill(tint.opacity(0.28))
                    .frame(width: 340, height: 340)
                    .blur(radius: 60)
                    .offset(
                        x: reduceMotion ? 0 : 18 * cos(t * 0.35),
                        y: reduceMotion ? -40 : -40 + 16 * sin(t * 0.28)
                    )
                Circle()
                    .fill(PulseTheme.accent.opacity(0.12))
                    .frame(width: 260, height: 260)
                    .blur(radius: 50)
                    .offset(
                        x: reduceMotion ? 60 : 60 + 22 * sin(t * 0.31),
                        y: reduceMotion ? 80 : 80 + 14 * cos(t * 0.4)
                    )
            }
        }
    }
}

// MARK: - Hold to talk

struct HoldToTalkButton: View {
    var onSend: (String) -> Void

    @State private var isPressed = false
    @State private var transcript = ""
    @State private var errorMessage: String?
    @State private var pulse = false
    @StateObject private var speech = SpeechCapture()

    var body: some View {
        VStack(spacing: 14) {
            Text(statusCopy)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(PulseTheme.mist)
                .animation(.easeOut(duration: 0.2), value: isPressed)

            ZStack {
                Circle()
                    .fill((isPressed ? Color.red : PulseTheme.accent).opacity(isPressed ? 0.32 : 0.14))
                    .blur(radius: isPressed ? 14 : 8)
                    .frame(width: isPressed ? 132 : 112, height: isPressed ? 132 : 112)
                    .scaleEffect(pulse && isPressed ? 1.1 : 1.0)
                    .animation(
                        isPressed
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.2),
                        value: pulse
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: isPressed
                                ? [
                                    Color(red: 1.0, green: 0.55, blue: 0.5),
                                    Color(red: 0.9, green: 0.22, blue: 0.32),
                                    Color(red: 0.55, green: 0.08, blue: 0.18)
                                ]
                                : [
                                    Color.white.opacity(0.55),
                                    PulseTheme.accent,
                                    Color(red: 0.2, green: 0.45, blue: 0.75)
                                ],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 56
                        )
                    )
                    .frame(width: 84, height: 84)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: (isPressed ? Color.red : PulseTheme.accent).opacity(0.5),
                        radius: isPressed ? 24 : 14,
                        y: 6
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        beginHold()
                    }
                    .onEnded { _ in
                        endHold()
                    }
            )
            .accessibilityLabel("Hold to talk")
            .accessibilityHint("Press and hold to speak, release to send")

            if !transcript.isEmpty {
                Text(transcript)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(PulseTheme.mist)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .lineLimit(3)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
            }
        }
    }

    private var statusCopy: String {
        if isPressed { return "Listening — release to send" }
        return "Hold to talk"
    }

    private func beginHold() {
        errorMessage = nil
        transcript = ""
        isPressed = true
        pulse = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        speech.start { result in
            switch result {
            case .success(let spoken):
                transcript = spoken
            case .failure(let error):
                errorMessage = error.localizedDescription
                isPressed = false
                pulse = false
            }
        }
    }

    private func endHold() {
        guard isPressed else { return }
        speech.stop()
        isPressed = false
        pulse = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = nil
            return
        }
        onSend(trimmed)
        transcript = ""
    }
}

@MainActor
final class SpeechCapture: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()

    func start(_ onPartial: @escaping (Result<String, Error>) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    onPartial(.failure(NSError(
                        domain: "VibeSignal",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Speech permission denied"]
                    )))
                    return
                }
                self.begin(onPartial: onPartial)
            }
        }
    }

    private func begin(onPartial: @escaping (Result<String, Error>) -> Void) {
        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onPartial(.failure(error))
            return
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onPartial(.failure(error))
            return
        }

        task = recognizer?.recognitionTask(with: request) { result, error in
            if let result {
                onPartial(.success(result.bestTranscription.formattedString))
            } else if let error {
                let ns = error as NSError
                if ns.domain == "kAFAssistantErrorDomain" && ns.code == 216 { return }
                if ns.code == 301 { return }
                onPartial(.failure(error))
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task?.cancel()
        request = nil
        task = nil
    }
}
