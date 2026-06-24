import AppKit
import AVFoundation
import Foundation
import ServiceManagement

/// The single user-facing speed/accuracy choice. Each mode maps to a
/// transcription engine + model. There is deliberately NO separate LLM cleanup
/// step: it kept punctuation cheap to add but cost whole seconds of latency.
/// Punctuation now comes from the engine itself, so dictation stays instant.
enum RecognitionMode: String, Codable, CaseIterable, Identifiable {
    case speed
    case accuracy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: return "Speed"
        case .accuracy: return "Accuracy"
        }
    }

    /// What you get, in one line — shown next to the choice in Settings.
    var summary: String {
        switch self {
        case .speed: return "Apple's native on-device recognition. Near-instant, private, no download."
        case .accuracy: return "Whisper turbo: more accurate for English and technical speech. Downloads once on first use."
        }
    }

    /// Rough delay after you stop talking, measured on Apple Silicon. Shown so
    /// the user can see the cost of each choice up front, not as guesswork.
    var latencyNote: String {
        switch self {
        case .speed: return "fastest"
        case .accuracy: return "≈ 0.5 s after you finish"
        }
    }

    var engineName: String {
        switch self {
        case .speed: return "Apple on-device"
        case .accuracy: return "Whisper turbo"
        }
    }

    /// Backing ASR engine id consumed by `Config.makeASREngine()`.
    var asrEngine: String {
        switch self {
        case .speed: return "apple"
        case .accuracy: return "whisperkit"
        }
    }

    /// WhisperKit model id (ignored by the Apple engine).
    var whisperModel: String {
        "large-v3-v20240930_turbo"
    }
}

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case dictate
    case translate
    case askAnything

    var id: String { rawValue }
}

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlagsRaw: UInt
    var displayName: String

    static let rightOption = KeyboardShortcut(
        keyCode: 61,
        modifierFlagsRaw: NSEvent.ModifierFlags.option.rawValue,
        displayName: "Right Option"
    )

    /// Supported hold-to-talk keys, offered as a simple dropdown. v0.2 backs
    /// modifier-only keys; detection keys off `keyCode` (see HotkeyMonitor).
    static let presets: [KeyboardShortcut] = [
        rightOption,
        modifierOnly(keyCode: 58, flag: .option, name: "Left Option"),
        modifierOnly(keyCode: 54, flag: .command, name: "Right Command"),
        modifierOnly(keyCode: 55, flag: .command, name: "Left Command"),
        modifierOnly(keyCode: 62, flag: .control, name: "Right Control"),
        modifierOnly(keyCode: 59, flag: .control, name: "Left Control"),
        modifierOnly(keyCode: 60, flag: .shift, name: "Right Shift"),
        modifierOnly(keyCode: 56, flag: .shift, name: "Left Shift"),
        modifierOnly(keyCode: 63, flag: .function, name: "Fn"),
    ]

    private static func modifierOnly(keyCode: UInt16, flag: NSEvent.ModifierFlags, name: String) -> KeyboardShortcut {
        KeyboardShortcut(keyCode: keyCode, modifierFlagsRaw: flag.rawValue, displayName: name)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
    }

    var isModifierOnly: Bool {
        modifierOnlyFlag != nil
    }

    var modifierOnlyFlag: NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .function
        default: return nil
        }
    }

    static func from(event: NSEvent) -> KeyboardShortcut? {
        if event.type == .flagsChanged, let flag = modifierFlag(for: event.keyCode) {
            return KeyboardShortcut(
                keyCode: event.keyCode,
                modifierFlagsRaw: flag.rawValue,
                displayName: modifierName(for: event.keyCode)
            )
        }

        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control, .function])
        guard !flags.isEmpty else { return nil }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        let name = [
            flags.contains(.command) ? "Command" : nil,
            flags.contains(.shift) ? "Shift" : nil,
            flags.contains(.option) ? "Option" : nil,
            flags.contains(.control) ? "Control" : nil,
            flags.contains(.function) ? "Fn" : nil,
            key,
        ].compactMap { $0 }.joined(separator: " + ")
        return KeyboardShortcut(keyCode: event.keyCode, modifierFlagsRaw: flags.rawValue, displayName: name)
    }

    private static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .function
        default: return nil
        }
    }

    private static func modifierName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 54: return "Right Command"
        case 55: return "Command"
        case 56: return "Shift"
        case 58: return "Option"
        case 59: return "Control"
        case 60: return "Right Shift"
        case 61: return "Right Option"
        case 62: return "Right Control"
        case 63: return "Fn"
        default: return "Key \(keyCode)"
        }
    }
}

struct PermissionSnapshot: Equatable {
    var microphone: AVAuthorizationStatus
    var accessibilityTrusted: Bool
    var inputMonitoringRequired: Bool = false
}

struct AppSettings: Codable, Equatable {
    var hasCompletedOnboarding: Bool
    var launchAtLogin: Bool
    var showMenuBarIcon: Bool
    var autoPaste: Bool
    var restoreClipboard: Bool
    var primaryShortcut: KeyboardShortcut
    var recognitionMode: RecognitionMode
    /// Persisted Core Audio device UID to record from; nil follows the macOS
    /// system default input. UIDs survive reboots/reconnects (unlike device IDs).
    var preferredInputDeviceUID: String?

    static let `default` = AppSettings(
        hasCompletedOnboarding: false,
        launchAtLogin: false,
        showMenuBarIcon: true,
        autoPaste: true,
        restoreClipboard: true,
        primaryShortcut: .rightOption,
        recognitionMode: .speed,
        preferredInputDeviceUID: nil
    )

    func asConfig() -> Config {
        Config(
            asrEngine: recognitionMode.asrEngine,
            whisperModel: recognitionMode.whisperModel,
            whisperLanguage: "auto"
        )
    }

    init(
        hasCompletedOnboarding: Bool,
        launchAtLogin: Bool,
        showMenuBarIcon: Bool,
        autoPaste: Bool,
        restoreClipboard: Bool,
        primaryShortcut: KeyboardShortcut,
        recognitionMode: RecognitionMode,
        preferredInputDeviceUID: String?
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.autoPaste = autoPaste
        self.restoreClipboard = restoreClipboard
        self.primaryShortcut = primaryShortcut
        self.recognitionMode = recognitionMode
        self.preferredInputDeviceUID = preferredInputDeviceUID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        autoPaste = try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? d.autoPaste
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? d.restoreClipboard
        primaryShortcut = try c.decodeIfPresent(KeyboardShortcut.self, forKey: .primaryShortcut) ?? d.primaryShortcut
        // Tolerate a retired mode value (e.g. an old "balanced") by falling back
        // to the default rather than discarding every other saved setting.
        recognitionMode = (try? c.decodeIfPresent(RecognitionMode.self, forKey: .recognitionMode)) ?? d.recognitionMode
        preferredInputDeviceUID = try c.decodeIfPresent(String.self, forKey: .preferredInputDeviceUID) ?? d.preferredInputDeviceUID
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    /// User-facing note about the Login Items state (approval needed, failure,
    /// etc.). `nil` when launch-at-login is in a clean state.
    @Published var launchAtLoginNotice: String?

    private var isLoading = false

    init() {
        settings = Self.loadSettings()
    }

    nonisolated static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/offlinevoice", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    nonisolated static func loadSettings() -> AppSettings {
        let url = fileURL
        if let data = try? Data(contentsOf: url),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return .default
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(settings).write(to: Self.fileURL)
            Log.write("saved settings to \(Self.fileURL.path)")
        } catch {
            Log.write("failed to save settings: \(error)")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        var failure: String?
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.write("launch at login update failed: \(error)")
            failure = "Couldn't update Login Items: \(error.localizedDescription)"
        }
        // Reconcile the toggle with the real system state, then surface any hard
        // failure last so it isn't overwritten by the status-derived notice.
        refreshLaunchAtLoginStatus(promptForApproval: enabled)
        if let failure { launchAtLoginNotice = failure }
    }

    /// Mirrors the persisted toggle onto the real ServiceManagement status so the
    /// UI never claims a state the system doesn't actually hold. Call at launch
    /// and after every toggle.
    func refreshLaunchAtLoginStatus(promptForApproval: Bool = false) {
        let status = SMAppService.mainApp.status
        let isEnabled = (status == .enabled)
        if settings.launchAtLogin != isEnabled {
            settings.launchAtLogin = isEnabled
        }
        switch status {
        case .enabled, .notRegistered:
            launchAtLoginNotice = nil
        case .requiresApproval:
            launchAtLoginNotice = "OfflineVoice needs approval in System Settings ▸ General ▸ Login Items."
            if promptForApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        case .notFound:
            launchAtLoginNotice = "Login Items registration wasn't found for this build."
        @unknown default:
            break
        }
    }
}
