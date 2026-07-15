import SwiftUI
import Speech
import AVFoundation
import UIKit
import Combine

/// Hold to speak, release to send. Empty release cancels.
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
                        domain: "Vibe Signal",
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
                // Ignore cancellation noise on release
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
