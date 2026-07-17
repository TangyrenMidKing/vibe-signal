import AVFoundation
import Foundation
import UIKit

/// Keeps the iPhone process runnable in the background so the LAN WebSocket
/// bridge to WatchConnectivity can stay alive after the screen locks.
///
/// Relies on `UIBackgroundModes = audio` plus a looping near-silent player
/// (same pattern as the Watch TTS playback session).
@MainActor
final class BackgroundBridge {
    private var player: AVAudioPlayer?
    private var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
    private var wantsKeepAlive = false
    private var suspendedForCapture = false

    func setEnabled(_ enabled: Bool) {
        wantsKeepAlive = enabled
        if enabled {
            startKeepAliveIfNeeded()
        } else {
            stopKeepAlive()
            endBackgroundTask()
        }
    }

    /// Speech recognition needs `.record`; pause the silent player first.
    func suspendForCapture() {
        suspendedForCapture = true
        player?.pause()
    }

    func resumeAfterCapture() {
        suspendedForCapture = false
        guard wantsKeepAlive else { return }
        startKeepAliveIfNeeded()
    }

    /// Extra ~30s of execution when iOS is about to suspend us.
    func beginBackgroundExecution() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "VibeSignalBridge") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }

    func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func startKeepAliveIfNeeded() {
        guard wantsKeepAlive, !suspendedForCapture else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            return
        }

        if let player, player.isPlaying { return }

        do {
            let player = try AVAudioPlayer(data: Self.silentWAV)
            player.numberOfLoops = -1
            // Zero volume can be optimized away; keep a barely-audible level.
            player.volume = 0.01
            player.prepareToPlay()
            guard player.play() else { return }
            self.player = player
        } catch {
            self.player = nil
        }
    }

    private func stopKeepAlive() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    /// 1s of 16-bit mono silence at 8 kHz.
    private static let silentWAV: Data = {
        let sampleRate = 8_000
        let channels = 1
        let bitsPerSample = 16
        let numSamples = sampleRate
        let dataSize = numSamples * channels * bitsPerSample / 8
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func appendASCII(_ s: String) {
            data.append(contentsOf: s.utf8)
        }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * channels * bitsPerSample / 8))
        appendUInt16(UInt16(channels * bitsPerSample / 8))
        appendUInt16(UInt16(bitsPerSample))
        appendASCII("data")
        appendUInt32(UInt32(dataSize))
        data.append(contentsOf: repeatElement(0, count: dataSize))
        return data
    }()
}
