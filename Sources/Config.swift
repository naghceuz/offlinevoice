import Foundation

/// Engine-level configuration derived from the user's `RecognitionMode`. Kept as
/// a small bridge so the ASR backends don't depend on the whole settings store.
struct Config: Codable {
    /// "sensevoice" (bundled, multilingual), "apple" (system-locale only) or
    /// "whisperkit" (downloads on first use).
    var asrEngine: String
    var whisperModel: String
    /// "auto" detects language; set "zh" to lock Chinese (fewer English mis-hears).
    var whisperLanguage: String

    /// Builds the ASR backend selected by the current recognition mode.
    func makeASREngine() -> ASREngine {
        switch asrEngine.lowercased() {
        case "apple": return AppleSpeechEngine()
        case "sensevoice": return SenseVoiceEngine()
        default: return WhisperKitEngine(model: whisperModel, language: whisperLanguage)
        }
    }
}

extension Config {
    /// Tolerant decoding: missing keys fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        asrEngine = try c.decodeIfPresent(String.self, forKey: .asrEngine) ?? d.asrEngine
        whisperModel = try c.decodeIfPresent(String.self, forKey: .whisperModel) ?? d.whisperModel
        whisperLanguage = try c.decodeIfPresent(String.self, forKey: .whisperLanguage) ?? d.whisperLanguage
    }

    static let `default` = Config(
        asrEngine: RecognitionMode.speed.asrEngine,
        whisperModel: RecognitionMode.speed.whisperModel,
        whisperLanguage: "auto"
    )

    /// Loads the engine config derived from the persisted recognition mode.
    static func load() -> Config {
        SettingsStore.loadSettings().asConfig()
    }
}
