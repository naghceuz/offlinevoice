import AVFoundation
import Foundation

#if DEBUG
/// DEBUG-only: writes each finished recording to /tmp as a 16 kHz mono WAV so
/// real dictations that mis-recognize can be replayed through the engines
/// offline. Never compiled into release builds — a release app must not keep
/// audio on disk. Keeps the last 20 captures.
enum CaptureDump {
    private static let directory = URL(fileURLWithPath: "/tmp/offlinevoice-captures", isDirectory: true)
    private static let keep = 20

    static func write(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let url = directory.appendingPathComponent("capture-\(stamp).wav")
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData
            else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { channel[0].update(from: base, count: samples.count) }
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            Log.write("capture saved: \(url.path)")
            prune()
        } catch {
            Log.write("capture dump failed: \(error)")
        }
    }

    private static func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let sorted = files.filter { $0.hasSuffix(".wav") }.sorted()
        for old in sorted.dropLast(keep) {
            try? fm.removeItem(at: directory.appendingPathComponent(old))
        }
    }
}
#endif
