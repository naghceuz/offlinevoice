import Foundation
import WhisperKit

/// Minimal, mockable view of a WhisperKit `WordTiming` — decouples the pure
/// punctuation logic from the WhisperKit module so it's unit-testable
/// without linking that package into the test target.
struct PauseWord: Equatable {
    let word: String
    let start: Float
    let end: Float
}

/// Same pause-based punctuation policy as `PausePunctuator` (shares its
/// gap thresholds and "already punctuated" mark set), but built directly by
/// concatenating WhisperKit's word timings instead of locating offsets in a
/// pre-formatted string. WhisperKit doesn't apply Apple-style ITN
/// reformatting, and joining `WordTiming.word` values in order with no
/// separator is WhisperKit's own supported reconstruction pattern (see
/// `TranscriptionUtilities.mergeTranscriptionResults` in the vendored
/// package) — English/Latin tokens carry their own leading space, CJK tokens
/// don't need one — so building the output straight from words is both
/// simpler and safe here.
enum WhisperPausePunctuator {
    static func apply(words: [PauseWord], language: String?) -> String {
        guard !words.isEmpty else { return "" }
        let isCJK = ["zh", "ja"].contains(language ?? "")

        var out = ""
        var capitalizeNext = false
        for (i, w) in words.enumerated() {
            var token = w.word
            if capitalizeNext, let idx = token.firstIndex(where: { !$0.isWhitespace }) {
                token.replaceSubrange(idx...idx, with: token[idx].uppercased())
            }
            capitalizeNext = false
            out += token

            guard i < words.count - 1 else { continue }
            let gap = words[i + 1].start - w.end
            guard gap > Float(PausePunctuator.commaGap) else { continue }

            // Don't double up if WhisperKit's own decoding already merged
            // punctuation onto either side of this boundary.
            let trimmedCurrent = token.trimmingCharacters(in: .whitespaces)
            if let last = trimmedCurrent.last, PausePunctuator.terminalMarks.contains(last) { continue }
            let trimmedNext = words[i + 1].word.trimmingCharacters(in: .whitespaces)
            if let first = trimmedNext.first, PausePunctuator.terminalMarks.contains(first) { continue }

            let isSentence = gap > Float(PausePunctuator.sentenceGap)
            if isCJK {
                out += isSentence ? "。" : "，"
            } else {
                out += isSentence ? "." : ","
                capitalizeNext = isSentence
            }
        }
        return out
    }
}

/// On-device transcription via WhisperKit (CoreML / Metal on Apple Silicon).
///
/// Loads strictly from the local cache with no network access — WhisperKit
/// otherwise hits Hugging Face during init to verify the tokenizer, which hangs
/// behind a system proxy. That defeats the whole point of an offline tool.
actor WhisperKitEngine: ASREngine {
    private var kit: WhisperKit?
    private let model: String
    private let language: String
    /// Per-component compute units (ANE/GPU/CPU). nil = WhisperKit defaults
    /// (encoder on ANE for macOS 14+). Only the benchmark passes this; the live
    /// engine keeps defaults.
    private let computeOptions: ModelComputeOptions?

    init(
        model: String = "large-v3-v20240930_turbo",
        language: String = "auto",
        computeOptions: ModelComputeOptions? = nil
    ) {
        self.model = model
        self.language = language
        self.computeOptions = computeOptions
    }

    private func loaded() async throws -> WhisperKit {
        if let kit { return kit }
        let config = Self.makeConfig(model: model, computeOptions: computeOptions)
        Log.write("loading WhisperKit model=\(model) offline=\(config.download == false)…")
        let kit = try await WhisperKit(config)
        self.kit = kit
        Log.write("WhisperKit model loaded")
        // Warm-up: run one inference on silence so Core ML's first-use ANE
        // specialization is paid here (inside prewarm) rather than stalling the
        // user's first real dictation. Best-effort — failure must not block ready.
        let warm = [Float](repeating: 0, count: 16_000)
        let warmLang = (language.lowercased() == "auto") ? nil : language.lowercased()
        _ = try? await kit.transcribe(
            audioArray: warm,
            decodeOptions: DecodingOptions(task: .transcribe, language: warmLang, detectLanguage: warmLang == nil)
        )
        Log.write("WhisperKit warm-up done")
        return kit
    }

    func prepare() async throws {
        _ = try await loaded()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let kit = try await loaded()
        let locked = (language.lowercased() == "auto") ? nil : language.lowercased()

        // Primary decode with WhisperKit's defaults.
        let text = try await decode(kit, samples, language: locked, relaxed: false)
        if !text.isEmpty { return text }

        // WhisperKit aborts a segment to an empty string when the first predicted
        // token's log-prob falls below firstTokenLogProbThreshold (-1.5) — and if
        // every temperature fallback hits that gate, the whole clip comes back
        // empty even on perfectly clear speech (an intermittent dropout). With
        // push-to-talk the user definitely spoke, so retry once with the
        // confidence gates disabled rather than silently dropping the dictation.
        Log.write("WhisperKit returned empty; retrying with confidence gates relaxed")
        return try await decode(kit, samples, language: locked, relaxed: true)
    }

    private func decode(
        _ kit: WhisperKit,
        _ samples: [Float],
        language locked: String?,
        relaxed: Bool
    ) async throws -> String {
        let options = DecodingOptions(
            task: .transcribe,
            language: locked,
            detectLanguage: locked == nil,
            wordTimestamps: true,
            firstTokenLogProbThreshold: relaxed ? nil : -1.5,
            noSpeechThreshold: relaxed ? nil : 0.6
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)

        let words = results.flatMap(\.allWords).map { PauseWord(word: $0.word, start: $0.start, end: $0.end) }
        guard !words.isEmpty else {
            // Word timestamps weren't populated for this decode (e.g. no
            // alignment weights available) — fall back to WhisperKit's own
            // text exactly as before this feature existed.
            return results
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return WhisperPausePunctuator.apply(words: words, language: results.first?.language)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Local-only config

    /// Builds a config that loads from the local Hugging Face cache and never
    /// touches the network. Falls back to the default (online) config if the
    /// cached model folder isn't present.
    private static func makeConfig(model: String, computeOptions: ModelComputeOptions?) -> WhisperKitConfig {
        #if os(iOS)
        // iOS has no shared HF cache and no homeDirectoryForCurrentUser; let
        // WhisperKit download into its own app-support location on first use,
        // then load locally thereafter. One-time download = still "offline" after.
        return WhisperKitConfig(model: model, computeOptions: computeOptions)
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent("Documents/huggingface/models")
        let modelFolder = base
            .appendingPathComponent("argmaxinc/whisperkit-coreml/openai_whisper-\(model)")
        let tokenizerFolder = base.appendingPathComponent("openai/whisper-large-v3")

        let fm = FileManager.default
        guard fm.fileExists(atPath: modelFolder.path) else {
            Log.write("local model folder missing, allowing download")
            return WhisperKitConfig(model: model, computeOptions: computeOptions)
        }
        return WhisperKitConfig(
            model: model,
            modelFolder: modelFolder.path,
            tokenizerFolder: fm.fileExists(atPath: tokenizerFolder.path) ? tokenizerFolder : nil,
            computeOptions: computeOptions,
            download: false
        )
        #endif
    }
}
