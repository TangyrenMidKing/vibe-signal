import SwiftUI
import WatchKit
import Speech
import AVFoundation

struct VoiceDictationView: View {
    var onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var holding = false
    @State private var cancelled = false
    @State private var isFinalizing = false
    @State private var pendingSendID: UUID?
    @StateObject private var speech = WatchSpeechCapture()

    var body: some View {
        VStack(spacing: 10) {
            Text(statusCopy)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PulseTheme.mist)
                .multilineTextAlignment(.center)

            Image(systemName: cancelled ? "xmark.circle.fill" : "mic.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(cancelled ? PulseTheme.signal(.error) : holding ? PulseTheme.signal(.working) : PulseTheme.accent)
                .scaleEffect(holding ? 1.12 : 1)
                .animation(.easeOut(duration: 0.15), value: holding)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !holding { beginHold() }
                            if value.translation.width < -40, !cancelled {
                                cancelHold()
                            }
                        }
                        .onEnded { _ in
                            if !cancelled { endHold() }
                        }
                )
                .accessibilityLabel("Hold to talk")
                .accessibilityHint("Slide left before releasing to cancel")

            if !text.isEmpty {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }

            Button("Cancel", role: .cancel) { dismiss() }
        }
        .padding(.horizontal, 4)
    }

    private var statusCopy: String {
        if cancelled { return "Cancelled" }
        if holding { return "Listening — slide left to cancel" }
        if isFinalizing { return "Transcribing..." }
        return "Hold to talk"
    }

    private func beginHold() {
        cancelled = false
        text = ""
        holding = true
        WKInterfaceDevice.current().play(.start)
        speech.start { result in
            switch result {
            case .success(let spoken): text = spoken
            case .failure: cancelHold()
            }
        }
    }

    private func cancelHold() {
        pendingSendID = nil
        speech.stop(cancelRecognition: true)
        holding = false
        isFinalizing = false
        cancelled = true
        text = ""
        WKInterfaceDevice.current().play(.failure)
    }

    private func endHold() {
        guard holding else { return }
        speech.stop()
        holding = false
        isFinalizing = true
        WKInterfaceDevice.current().play(.click)
        let sendID = UUID()
        pendingSendID = sendID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard pendingSendID == sendID else { return }
            pendingSendID = nil
            isFinalizing = false
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onText(trimmed)
            dismiss()
        }
    }
}

@MainActor
final class WatchSpeechCapture: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var startAttempt = UUID()

    func start(_ onPartial: @escaping (Result<String, Error>) -> Void) {
        let attempt = UUID()
        startAttempt = attempt
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard self.startAttempt == attempt, status == .authorized else { return }
                self.begin(onPartial: onPartial)
            }
        }
    }

    private func begin(onPartial: @escaping (Result<String, Error>) -> Void) {
        stop(cancelRecognition: true)
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else { return }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let input = audioEngine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            onPartial(.failure(error))
            return
        }
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { onPartial(.success(result.bestTranscription.formattedString)) }
            if let error { onPartial(.failure(error)) }
        }
    }

    func stop(cancelRecognition: Bool = false) {
        startAttempt = UUID()
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        if cancelRecognition { task?.cancel() }
        request = nil
        task = nil
        recognizer = nil
    }
}
