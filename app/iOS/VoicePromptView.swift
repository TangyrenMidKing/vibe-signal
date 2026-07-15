import SwiftUI
import Speech
import AVFoundation

struct VoicePromptView: View {
    var onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isListening = false
    @State private var errorMessage: String?
    @State private var recognizer = SpeechHelper()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(isListening ? "Listening…" : "Tap the mic, then speak a prompt")
                    .foregroundStyle(.secondary)

                Button {
                    toggleListen()
                } label: {
                    Image(systemName: isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(isListening ? Color.red : Color.accentColor)
                }

                TextEditor(text: $text)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }

                Button("Send") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onText(trimmed)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Voice Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        recognizer.stop()
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleListen() {
        if isListening {
            recognizer.stop()
            isListening = false
            return
        }
        errorMessage = nil
        recognizer.start { result in
            switch result {
            case .success(let spoken):
                text = spoken
            case .failure(let error):
                errorMessage = error.localizedDescription
                isListening = false
            }
        }
        isListening = true
    }
}

final class SpeechHelper {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()

    func start(_ onPartial: @escaping (Result<String, Error>) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    onPartial(.failure(NSError(domain: "AgentPulse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech permission denied"])))
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
            }
            if let error {
                onPartial(.failure(error))
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
