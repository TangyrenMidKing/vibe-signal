import Foundation
import Security

enum OpenAIVoice: String, CaseIterable, Identifiable {
    case nova
    case alloy
    case echo
    case fable
    case onyx
    case shimmer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nova: return "Nova"
        case .alloy: return "Alloy"
        case .echo: return "Echo"
        case .fable: return "Fable"
        case .onyx: return "Onyx"
        case .shimmer: return "Shimmer"
        }
    }
}

enum OpenAITTSError: LocalizedError {
    case missingAPIKey
    case badStatus(Int, String)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key in the Vibe Signal menu"
        case .badStatus(let code, let body):
            return "OpenAI TTS failed (\(code)): \(body)"
        case .emptyAudio:
            return "OpenAI TTS returned empty audio"
        }
    }
}

/// OpenAI Audio Speech API → mp3 data for Watch playback.
enum OpenAITTS {
    private static let keychainService = "com.vibesignal.openai"
    private static let keychainAccount = "apiKey"
    private static let voiceDefaultsKey = "vibesignal.openaiVoice"

    static var apiKey: String? {
        get { readKey() }
        set {
            if let newValue, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                saveKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                deleteKey()
            }
        }
    }

    static var hasAPIKey: Bool {
        !(apiKey ?? "").isEmpty
    }

    static var voice: OpenAIVoice {
        get {
            let raw = UserDefaults.standard.string(forKey: voiceDefaultsKey) ?? OpenAIVoice.nova.rawValue
            return OpenAIVoice(rawValue: raw) ?? .nova
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: voiceDefaultsKey)
        }
    }

    /// Synthesize `text` to an mp3 file URL. Caller owns cleanup.
    static func synthesizeToFile(_ text: String) async throws -> URL {
        guard let key = apiKey, !key.isEmpty else { throw OpenAITTSError.missingAPIKey }

        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw OpenAITTSError.emptyAudio }
        // API limit 4096; keep wrist replies shorter for latency + transfer size.
        if input.count > 1200 {
            input = String(input.prefix(1200))
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "tts-1-hd",
            "input": input,
            "voice": voice.rawValue,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw OpenAITTSError.badStatus(status, String(message.prefix(180)))
        }
        guard !data.isEmpty else { throw OpenAITTSError.emptyAudio }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe-tts-\(UUID().uuidString)")
            .appendingPathExtension("mp3")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Keychain

    private static func saveKey(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func readKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
