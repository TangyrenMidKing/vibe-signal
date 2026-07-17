import SwiftUI
import WatchKit
import AVFoundation

struct WatchStatusView: View {
    @EnvironmentObject private var model: WatchModel

    private var disconnected: Bool {
        !model.phoneReachable && model.snapshot.state == .idle
    }

    private var state: AgentState {
        disconnected ? .idle : model.snapshot.state
    }

    private var signal: Color {
        PulseTheme.signal(state)
    }

    private var headline: String {
        disconnected ? "Offline" : state.title
    }

    private var detail: String {
        disconnected ? "Open Vibe Signal on iPhone" : model.snapshot.state.pulseLabel
    }

    var body: some View {
        ZStack {
            // Soft full-screen wash per state (muted so text stays readable).
            PulseTheme.ink.ignoresSafeArea()
            signal
                .opacity(0.8)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: state)

            VStack(spacing: 0) {
                statusHeader

                Spacer(minLength: 6)

                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseTheme.mist)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)

                if let project = model.snapshot.project, !project.isEmpty, !disconnected {
                    Text(project)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(PulseTheme.mistSoft)
                        .lineLimit(1)
                        .padding(.top, 4)
                }

                Spacer(minLength: 8)

                if !disconnected {
                    controls
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(signal)
                .frame(width: 8, height: 8)
                .shadow(color: signal.opacity(0.6), radius: 4)

            Text(headline.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controls: some View {
        switch model.snapshot.state {
        case .waiting:
            HStack(spacing: 7) {
                actionButton("Approve", icon: "checkmark") { model.send(.approve) }
                    .tint(PulseTheme.signal(.completed))
                actionButton("Decline", icon: "xmark") { model.send(.deny) }
                    .tint(PulseTheme.signal(.working))
            }
        default:
            // Stop while reading a reply, or while Codex is working.
            if model.isReadingReply || model.snapshot.state == .working {
                stopButton
            } else {
                WatchHoldToTalkButton { url in
                    model.sendVoiceRecording(url)
                }
            }
        }
    }

    private var stopButton: some View {
        VStack(spacing: 6) {
            Text(model.isReadingReply ? "Tap to stop" : "Stop agent")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PulseTheme.mist)
                .frame(maxWidth: .infinity)

            Button {
                if model.isReadingReply {
                    model.stopSpeaking()
                }
                if model.snapshot.state == .working || model.snapshot.state == .waiting {
                    model.send(.stop)
                }
                WKInterfaceDevice.current().play(.click)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.35))
                        .frame(width: 64, height: 64)
                        .blur(radius: 6)

                    Circle()
                        .fill(Color.red.opacity(0.9))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        )

                    Image(systemName: "stop.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isReadingReply ? "Stop reading" : "Stop Codex")
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }
}

// MARK: - Hold to talk (same interaction as iPhone)

/// Hold → record, release → send audio to iPhone for transcription.
/// watchOS has no Speech framework, so recognition happens on the phone.
private struct WatchHoldToTalkButton: View {
    var onSend: (URL) -> Void

    @EnvironmentObject private var model: WatchModel
    @StateObject private var recorder = WatchAudioCapture()
    @State private var isPressed = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var holdGeneration = 0

    var body: some View {
        VStack(spacing: 6) {
            Text(statusCopy)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(errorMessage == nil ? PulseTheme.mist : Color(red: 1, green: 0.45, blue: 0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            ZStack {
                Circle()
                    .fill((isPressed ? Color.red : PulseTheme.accent).opacity(isPressed ? 0.35 : 0.16))
                    .frame(width: isPressed ? 72 : 64, height: isPressed ? 72 : 64)
                    .blur(radius: 6)

                Circle()
                    .fill(isPressed ? Color.red.opacity(0.9) : PulseTheme.accent)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed, !isSending else { return }
                        beginHold()
                    }
                    .onEnded { _ in
                        endHold()
                    }
            )
            .accessibilityLabel("Hold to talk")
            .accessibilityHint("Press and hold to speak, release to send")
        }
        .onAppear { recorder.prewarmPermission() }
    }

    private var statusCopy: String {
        if let errorMessage, !errorMessage.isEmpty { return errorMessage }
        if let modelError = model.speechError, !modelError.isEmpty { return modelError }
        if isPressed { return "Listening — release to send" }
        if isSending { return "Sending…" }
        return "Hold to talk"
    }

    private func beginHold() {
        errorMessage = nil
        model.clearSpeechError()
        model.stopSpeaking()
        isPressed = true
        holdGeneration += 1
        let generation = holdGeneration
        WKInterfaceDevice.current().play(.start)

        recorder.startIfAllowed { result in
            guard isPressed, generation == holdGeneration else {
                _ = recorder.discard()
                return
            }
            if case .failure(let error) = result {
                isPressed = false
                errorMessage = error.localizedDescription
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private func endHold() {
        guard isPressed else { return }
        isPressed = false
        holdGeneration += 1
        WKInterfaceDevice.current().play(.click)

        guard let url = recorder.stop() else {
            errorMessage = "No speech detected. Hold, speak, then release."
            WKInterfaceDevice.current().play(.failure)
            return
        }

        isSending = true
        onSend(url)
        // Brief "Sending…" state so release feedback matches iPhone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isSending = false
        }
    }
}

@MainActor
private final class WatchAudioCapture: ObservableObject {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var permission: Permission = .unknown

    private enum Permission {
        case unknown, granted, denied
    }

    func prewarmPermission() {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            permission = .granted
        case .denied:
            permission = .denied
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    self?.permission = granted ? .granted : .denied
                }
            }
        @unknown default:
            break
        }
    }

    func startIfAllowed(completion: @escaping (Result<Void, Error>) -> Void) {
        let begin = { [weak self] in
            guard let self else { return }
            do {
                try self.startRecording()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }

        switch permission {
        case .granted:
            begin()
        case .denied:
            completion(.failure(Self.error("Enable Microphone in Watch Settings")))
        case .unknown:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    self?.permission = granted ? .granted : .denied
                    guard granted else {
                        completion(.failure(Self.error("Microphone access is required")))
                        return
                    }
                    begin()
                }
            }
        }
    }

    private func startRecording() throws {
        _ = discard()
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-prompt-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw Self.error("Could not start recording")
        }
        self.recorder = recorder
        recordingURL = url
        startedAt = Date()
    }

    func stop() -> URL? {
        guard let recorder else { return nil }
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        if recorder.isRecording { recorder.stop() }
        self.recorder = nil
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        defer { recordingURL = nil }
        guard let url = recordingURL else { return nil }

        // Match iPhone feel: short taps don't count as speech.
        if elapsed < 0.35 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size < 600 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    @discardableResult
    func discard() -> URL? {
        if let recorder, recorder.isRecording { recorder.stop() }
        self.recorder = nil
        startedAt = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return nil
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "VibeSignal", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
