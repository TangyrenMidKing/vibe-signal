import SwiftUI
import Speech
import AVFoundation
import UIKit
import Combine

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPairing = false
    @State private var showManual = false
    @State private var showFeedback = false
    @State private var showOpenAIKey = false
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

                SignalHero(
                    snapshot: model.snapshot,
                    connected: model.isConnected,
                    onShowFeedback: { showFeedback = true }
                )
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                    .animation(.easeOut(duration: 0.45), value: appear)

                Spacer(minLength: 16)

                contextActions
                    .padding(.horizontal, 20)

                if let err = model.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
            }
            // Unlike an overlay, a safe-area inset takes real layout space.
            // Continue/Retry therefore remain above the transcript while the
            // mic itself stays anchored at the bottom of the screen.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HoldToTalkButton(language: model.speechLanguage) { text in
                    model.send(.voice_prompt, text: text)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
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
        .sheet(isPresented: $showFeedback) {
            FeedbackLogView(text: model.snapshot.detail)
        }
        .sheet(isPresented: $showOpenAIKey) {
            OpenAIKeyView(
                hasKey: model.hasOpenAIKey,
                onSave: { key in
                    model.setOpenAIAPIKey(key)
                    showOpenAIKey = false
                },
                onClear: {
                    model.clearOpenAIAPIKey()
                    showOpenAIKey = false
                }
            )
        }
        .onAppear {
            appear = true
            if model.needsPairing {
                showPairing = true
            }
        }
    }

    private var background: some View {
        PulseTheme.ink
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vibe Signal")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.02)
                    .foregroundStyle(.white)
                Text(linkSubtitle)
                    .font(.caption)
                    .foregroundStyle(PulseTheme.mistSoft)
            }
            Spacer()
            Menu {
                Button("Scan QR", systemImage: "qrcode.viewfinder") { showPairing = true }
                Button("Enter Manually", systemImage: "keyboard") { showManual = true }
                Menu("Speech language", systemImage: "waveform") {
                    ForEach(SpeechLanguage.allCases) { language in
                        Button {
                            model.setSpeechLanguage(language)
                        } label: {
                            Label(
                                language.title,
                                systemImage: model.speechLanguage == language
                                    ? "checkmark"
                                    : "circle"
                            )
                        }
                    }
                }
                Divider()
                Button(
                    model.hasOpenAIKey ? "OpenAI API Key ✓" : "OpenAI API Key…",
                    systemImage: "key.fill"
                ) {
                    showOpenAIKey = true
                }
                Menu("Watch reply voice", systemImage: "speaker.wave.2.fill") {
                    ForEach(OpenAIVoice.allCases) { voice in
                        Button {
                            model.setOpenAIVoice(voice)
                        } label: {
                            Label(
                                voice.title,
                                systemImage: model.openAIVoice == voice
                                    ? "checkmark"
                                    : "circle"
                            )
                        }
                    }
                }
                .disabled(!model.hasOpenAIKey)
                if model.pairing != nil {
                    Divider()
                    Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
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

    private var linkSubtitle: String {
        if model.isConnected { return "Linked to desktop" }
        if model.pairing != nil { return "Reconnecting…" }
        return "Not linked"
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
    var onShowFeedback: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            SignalDial(state: snapshot.state)

            VStack(spacing: 8) {
                Text(snapshot.state.pulseLabel.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(PulseTheme.signal(snapshot.state))

                Text(snapshot.state.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.02)
                    .foregroundStyle(.white)

                ProjectRepoChips(project: snapshot.project, repo: snapshot.repo)

                Text(snapshot.detail)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(PulseTheme.mist)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .lineLimit(3)

                if snapshot.state == .completed || snapshot.state == .error {
                    Button("View full response", systemImage: "text.alignleft") {
                        onShowFeedback()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PulseTheme.accent)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(connected ? PulseTheme.signal(.completed) : PulseTheme.signal(.idle))
                        .frame(width: 7, height: 7)
                    Text(connected ? "Live" : "Reconnecting…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PulseTheme.mistSoft)
                }
                .padding(.top, 4)
            }
        }
    }
}

/// A flat, readable state indicator: closer to a field instrument than a
/// decorative 3D object. State is conveyed by icon, label, and color.
struct SignalDial: View {
    let state: AgentState

    private var tint: Color { PulseTheme.signal(state) }

    private var symbol: String {
        switch state {
        case .idle: return "pause.fill"
        case .working: return "bolt.fill"
        case .waiting: return "exclamationmark"
        case .completed: return "checkmark"
        case .error: return "xmark"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(PulseTheme.inkElevated)
                .frame(width: 118, height: 118)

            Circle()
                .stroke(PulseTheme.line, lineWidth: 1)
                .frame(width: 118, height: 118)

            Circle()
                .trim(from: 0.08, to: state == .idle ? 0.32 : 0.92)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 100, height: 100)
                .animation(.easeOut(duration: 0.25), value: state)

            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == 1 && state == .working ? tint : PulseTheme.line)
                        .frame(width: 14, height: 3)
                }
            }
            .offset(y: 37)
        }
        .accessibilityLabel(state.title)
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

// MARK: - Hold to talk

struct HoldToTalkButton: View {
    let language: SpeechLanguage
    var onSend: (String) -> Void

    @State private var isPressed = false
    @State private var transcript = ""
    @State private var errorMessage: String?
    @State private var pulse = false
    @State private var isFinalizing = false
    @State private var pendingSendID: UUID?
    @StateObject private var speech = SpeechCapture()

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(PulseTheme.mist)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .bottom)

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
        }
    }

    private var statusCopy: String {
        if isPressed { return "Listening — release to send" }
        if isFinalizing { return "Transcribing..." }
        return "Hold to talk"
    }

    private func beginHold() {
        pendingSendID = nil
        errorMessage = nil
        transcript = ""
        isPressed = true
        isFinalizing = false
        pulse = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        speech.start(localeIdentifier: language.localeIdentifier) { result in
            switch result {
            case .success(let spoken):
                transcript = spoken
            case .failure(let error):
                pendingSendID = nil
                errorMessage = error.localizedDescription
                isPressed = false
                pulse = false
                isFinalizing = false
            }
        }
    }

    private func endHold() {
        guard isPressed else { return }
        speech.stop()
        isPressed = false
        pulse = false
        isFinalizing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let sendID = UUID()
        pendingSendID = sendID

        // The recognizer often returns the final words just after audio ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard pendingSendID == sendID else { return }
            pendingSendID = nil
            isFinalizing = false
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "No speech detected. Hold, speak, then release."
                return
            }
            onSend(trimmed)
            transcript = ""
        }
    }
}

@MainActor
final class SpeechCapture: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var startAttempt = UUID()

    func start(
        localeIdentifier: String,
        _ onPartial: @escaping (Result<String, Error>) -> Void
    ) {
        let attempt = UUID()
        startAttempt = attempt
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard self.startAttempt == attempt else { return }
                guard status == .authorized else {
                    onPartial(.failure(NSError(
                        domain: "VibeSignal",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Speech permission denied"]
                    )))
                    return
                }
                self.begin(localeIdentifier: localeIdentifier, onPartial: onPartial)
            }
        }
    }

    private func begin(
        localeIdentifier: String,
        onPartial: @escaping (Result<String, Error>) -> Void
    ) {
        stop(cancelRecognition: true)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            onPartial(.failure(NSError(
                domain: "VibeSignal",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable for this language"]
            )))
            return
        }
        self.recognizer = recognizer
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

        task = recognizer.recognitionTask(with: request) { result, error in
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

    func stop(cancelRecognition: Bool = false) {
        // Do not start recording after a quick press-and-release while iOS is
        // still resolving microphone/speech authorization.
        startAttempt = UUID()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        if cancelRecognition {
            task?.cancel()
        }
        request = nil
        task = nil
        recognizer = nil
    }
}

// MARK: - OpenAI API key (inlined so Xcode picks it up without xcodegen)

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
