import SwiftUI
import WatchKit
import AVFoundation

struct WatchStatusView: View {
    @EnvironmentObject private var model: WatchModel
    @State private var isHoldingSpeak = false
    @State private var speechError: String?
    @StateObject private var recorder = WatchAudioCapture()

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
            PulseTheme.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                statusHeader

                Spacer(minLength: 8)

                Text(speechError ?? (isHoldingSpeak ? "Listening…" : detail))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseTheme.mist)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)

                if let project = model.snapshot.project, !project.isEmpty, !disconnected {
                    Text(project)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(PulseTheme.mistSoft)
                        .lineLimit(1)
                        .padding(.top, 5)
                }

                Spacer(minLength: 10)

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
        case .completed, .error:
            HStack(spacing: 7) {
                actionButton("Continue", icon: "arrow.right") { model.send(.continue) }
                    .tint(PulseTheme.accent)
                speakButton
            }
        default:
            speakButton
        }
    }

    private var speakButton: some View {
        Label(isHoldingSpeak ? "Listening" : "Hold to speak", systemImage: "mic.fill")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(PulseTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(isHoldingSpeak ? PulseTheme.accent.opacity(0.78) : PulseTheme.accent)
            .clipShape(Capsule())
            .scaleEffect(isHoldingSpeak ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: isHoldingSpeak)
            .gesture(holdToTalk)
            .accessibilityLabel("Hold to speak")
            .accessibilityHint("Press and hold to dictate; release to send")
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

    private var holdToTalk: some Gesture {
        LongPressGesture(minimumDuration: 0, maximumDistance: 24)
            .onChanged { _ in beginHold() }
            .onEnded { _ in endHold() }
    }

    private func beginHold() {
        guard !isHoldingSpeak else { return }
        speechError = nil
        do {
            try recorder.start()
            isHoldingSpeak = true
            WKInterfaceDevice.current().play(.start)
        } catch {
            speechError = error.localizedDescription
        }
    }

    private func endHold() {
        guard isHoldingSpeak else { return }
        isHoldingSpeak = false
        WKInterfaceDevice.current().play(.click)
        guard let recording = recorder.stop() else { return }
        model.sendVoiceRecording(recording)
    }
}

@MainActor
private final class WatchAudioCapture: ObservableObject {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func start() throws {
        _ = stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
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
            throw NSError(domain: "VibeSignal", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not start recording"])
        }
        self.recorder = recorder
        recordingURL = url
    }

    func stop() -> URL? {
        guard let recorder, recorder.isRecording else { return nil }
        recorder.stop()
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { recordingURL = nil }
        return recordingURL
    }
}
