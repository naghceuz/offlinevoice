import CryptoKit
import Foundation
import SherpaOnnx
import SherpaOnnxC

/// On-device transcription via SenseVoiceSmall running in sherpa-onnx
/// (onnxruntime, CPU). One model covers Mandarin, Cantonese, English, Japanese
/// and Korean with automatic language identification, including mixed
/// Chinese/English in a single utterance — the case the single-locale Apple
/// recognizer cannot handle. Non-autoregressive, so decoding cost is roughly
/// linear in audio length. Inverse text normalization is on, so the model
/// emits punctuation and digits itself.
///
/// The model files ship inside the app bundle (`Resources/models/sense-voice`,
/// fetched by `scripts/fetch-models.sh`; provenance and licence in
/// `Resources/SenseVoice-NOTICE.md`). Nothing is downloaded at runtime.
///
/// Uses the sherpa-onnx C API directly rather than `SherpaOnnxOfflineRecognizer`
/// from the Swift wrapper: the wrapper calls `fatalError` when the recognizer
/// cannot be created. Even the C API is not fully recoverable, though —
/// probing showed a *missing* model returns nil, but a *truncated/corrupt*
/// model raises an uncaught C++ exception and a swapped tokens file calls
/// `exit()`. So every file is verified against its pinned SHA-256 before any
/// sherpa-onnx call; only a verified set ever reaches the C API.
actor SenseVoiceEngine: ASREngine {
    private var recognizer: OpaquePointer?
    private let numThreads: Int

    /// Where the bundled model lives. Overridable for tests/benchmarks.
    private let modelDirectory: URL?

    static let bundledModelSubpath = "models/sense-voice"

    /// Pinned upstream files (see Resources/SenseVoice-NOTICE.md). Must match
    /// scripts/fetch-models.sh exactly.
    static let expectedFiles: [(name: String, size: Int, sha256: String)] = [
        ("model.int8.onnx", 239_233_841, "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"),
        ("tokens.txt", 315_894, "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"),
    ]

    init(modelDirectory: URL? = nil, numThreads: Int = 4) {
        self.modelDirectory = modelDirectory
        self.numThreads = numThreads
    }

    func prepare() async throws {
        _ = try loaded()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let rec = try loaded()
        guard let stream = SherpaOnnxCreateOfflineStream(rec) else {
            throw err("SenseVoice could not create a decoding stream.")
        }
        defer { SherpaOnnxDestroyOfflineStream(stream) }

        SherpaOnnxAcceptWaveformOffline(stream, 16_000, samples, Int32(samples.count))
        SherpaOnnxDecodeOfflineStream(rec, stream)

        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw err("SenseVoice returned no result.")
        }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }

        let text = result.pointee.text.map { String(cString: $0) } ?? ""
        let lang = result.pointee.lang.map { String(cString: $0) } ?? "?"
        // Privacy: log the detected language and length only, never the text.
        Log.write("SenseVoice decoded lang=\(lang) chars=\(text.count)")
        return TranscriptCleaner.apply(text)
    }

    // MARK: - Loading

    private func loaded() throws -> OpaquePointer {
        if let recognizer { return recognizer }

        let dir = try resolveModelDirectory()
        let model = dir.appendingPathComponent("model.int8.onnx")
        let tokens = dir.appendingPathComponent("tokens.txt")

        let start = CFAbsoluteTimeGetCurrent()
        try verifyModelFiles(in: dir)
        Log.write("SenseVoice model files verified in \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000)) ms, loading threads=\(numThreads)…")
        let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: model.path,
            language: "auto",
            useInverseTextNormalization: true
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokens.path,
            numThreads: numThreads,
            provider: "cpu",
            debug: 0,
            senseVoice: senseVoice
        )
        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: modelConfig
        )
        guard let rec = SherpaOnnxCreateOfflineRecognizer(&config) else {
            throw err("SenseVoice model failed to load (corrupt or incompatible model files).")
        }
        recognizer = rec
        Log.write("SenseVoice ready in \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000)) ms")

        // Warm-up on one second of silence so onnxruntime's first-run setup is
        // paid here rather than on the user's first dictation. Best-effort.
        if let stream = SherpaOnnxCreateOfflineStream(rec) {
            let silence = [Float](repeating: 0, count: 16_000)
            SherpaOnnxAcceptWaveformOffline(stream, 16_000, silence, Int32(silence.count))
            SherpaOnnxDecodeOfflineStream(rec, stream)
            SherpaOnnxDestroyOfflineStream(stream)
        }
        return rec
    }

    /// Refuses to hand sherpa-onnx anything but the exact pinned files: a
    /// corrupt model crashes the process inside onnxruntime (uncaught C++
    /// exception), which no Swift error handling can catch after the fact.
    private func verifyModelFiles(in dir: URL) throws {
        let fm = FileManager.default
        for file in Self.expectedFiles {
            let url = dir.appendingPathComponent(file.name)
            guard fm.isReadableFile(atPath: url.path) else {
                throw err("Bundled SenseVoice model is missing (\(file.name)). Run scripts/fetch-models.sh and rebuild.")
            }
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
            guard size == file.size else {
                throw err("Bundled SenseVoice model file \(file.name) has the wrong size (\(size) bytes). Reinstall OfflineVoice.")
            }
            guard try Self.sha256Hex(of: url) == file.sha256 else {
                throw err("Bundled SenseVoice model file \(file.name) failed its integrity check. Reinstall OfflineVoice.")
            }
        }
    }

    /// Streaming SHA-256 so the 228 MB model is never held in memory twice.
    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 4 * 1024 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func resolveModelDirectory() throws -> URL {
        if let modelDirectory { return modelDirectory }
        guard let resources = Bundle.main.resourceURL else {
            throw err("App bundle has no Resources directory.")
        }
        return resources.appendingPathComponent(Self.bundledModelSubpath, isDirectory: true)
    }

    private func err(_ message: String) -> NSError {
        NSError(domain: "OfflineVoice.SenseVoice", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
