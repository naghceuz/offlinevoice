import CryptoKit
import Foundation
import SherpaOnnx
import SherpaOnnxC

/// Decides whether a capture contains speech at all, before it reaches the
/// transcription engine. Push-to-talk makes accidental taps common, and a
/// speech model given a second of room noise does not return "" — SenseVoice
/// answered "The." and "你。" to three such taps during testing, and those
/// got pasted into the user's document. A fixed amplitude threshold cannot
/// separate "quiet room" from "quiet speaker" across microphones, so this
/// uses Silero VAD (bundled, 0.6 MB, see Resources/SileroVAD-NOTICE.md).
///
/// Same safety rule as `SenseVoiceEngine`: the model file is verified against
/// its pinned SHA-256 before sherpa-onnx ever sees it.
actor SpeechGate {
    static let bundledModelSubpath = "models/silero-vad"
    static let expectedFile = (name: "silero_vad.onnx", size: 643_854,
                               sha256: "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6")

    /// Silero decides per 512-sample window (32 ms at 16 kHz); a run of speech
    /// windows at least this long counts. Short enough for a one-word answer.
    private let minSpeechDuration: Float = 0.25
    private let threshold: Float = 0.5

    private var vad: OpaquePointer?
    private let modelDirectory: URL?

    init(modelDirectory: URL? = nil) {
        self.modelDirectory = modelDirectory
    }

    func prepare() throws {
        _ = try loaded()
    }

    /// True when at least one speech segment is detected in `samples` (16 kHz
    /// mono). Throws only when the model cannot be loaded; callers decide
    /// whether to fail open or closed.
    func containsSpeech(_ samples: [Float]) throws -> Bool {
        let vad = try loaded()
        SherpaOnnxVoiceActivityDetectorReset(vad)
        // Feed in window-sized chunks; the detector keeps its own state.
        let window = 512
        var index = 0
        while index < samples.count {
            let end = min(index + window, samples.count)
            let chunk = Array(samples[index..<end])
            SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, chunk, Int32(chunk.count))
            index = end
        }
        SherpaOnnxVoiceActivityDetectorFlush(vad)
        let found = SherpaOnnxVoiceActivityDetectorEmpty(vad) == 0
        // Drain so the next call starts clean even without reset().
        while SherpaOnnxVoiceActivityDetectorEmpty(vad) == 0 {
            SherpaOnnxVoiceActivityDetectorPop(vad)
        }
        return found
    }

    // MARK: - Loading

    private func loaded() throws -> OpaquePointer {
        if let vad { return vad }
        let dir = try resolveModelDirectory()
        let model = dir.appendingPathComponent(Self.expectedFile.name)
        try Self.verify(model)

        let silero = sherpaOnnxSileroVadModelConfig(
            model: model.path,
            threshold: threshold,
            minSilenceDuration: 0.25,
            minSpeechDuration: minSpeechDuration,
            windowSize: 512,
            maxSpeechDuration: 30
        )
        var config = sherpaOnnxVadModelConfig(sileroVad: silero, sampleRate: 16_000, numThreads: 1, provider: "cpu", debug: 0)
        guard let created = SherpaOnnxCreateVoiceActivityDetector(&config, 60) else {
            throw err("Silero VAD failed to load (corrupt or incompatible model file).")
        }
        vad = created
        Log.write("SpeechGate ready (Silero VAD)")
        return created
    }

    private static func verify(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: url.path) else {
            throw NSError(domain: "OfflineVoice.SpeechGate", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundled Silero VAD model is missing (\(url.lastPathComponent)). Run scripts/fetch-models.sh and rebuild.",
            ])
        }
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        guard size == expectedFile.size else {
            throw NSError(domain: "OfflineVoice.SpeechGate", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundled Silero VAD model has the wrong size (\(size) bytes). Reinstall OfflineVoice.",
            ])
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedFile.sha256 else {
            throw NSError(domain: "OfflineVoice.SpeechGate", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundled Silero VAD model failed its integrity check. Reinstall OfflineVoice.",
            ])
        }
    }

    private func resolveModelDirectory() throws -> URL {
        if let modelDirectory { return modelDirectory }
        guard let resources = Bundle.main.resourceURL else {
            throw err("App bundle has no Resources directory.")
        }
        return resources.appendingPathComponent(Self.bundledModelSubpath, isDirectory: true)
    }

    private func err(_ message: String) -> NSError {
        NSError(domain: "OfflineVoice.SpeechGate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
