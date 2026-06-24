import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var pipelineState: Pipeline.State = .idle
    @Published var isModelReady = false
    @Published var modelError: String?
    /// True after a dictation couldn't be auto-pasted for lack of Accessibility.
    @Published var pasteBlockedByAccessibility = false
    /// Set when a recording came through near-silent — the input device is likely
    /// wrong or busy (e.g. AirPods held by a phone). nil when capture is healthy.
    @Published var audioInputWarning: String?
    @Published var permissions = PermissionSnapshot(
        microphone: AVCaptureDevice.authorizationStatus(for: .audio),
        accessibilityTrusted: AXIsProcessTrusted()
    )
    @Published var testRecordingActive = false

    let settingsStore: SettingsStore

    var openAccessibilitySettings: () -> Void = {}
    var openMicrophoneSettings: () -> Void = {}
    var startDictation: () -> Void = {}
    var stopDictation: () -> Void = {}
    var refreshHealth: () -> Void = {}
    var retryModelLoad: () -> Void = {}
    /// Developer-only: kick off the engine benchmark (DEBUG button / --benchmark).
    var runBenchmark: () -> Void = {}

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    var statusText: String {
        if !permissions.accessibilityTrusted { return "Accessibility permission needed" }
        if permissions.microphone != .authorized { return "Microphone permission needed" }
        switch pipelineState {
        case .loadingModel: return "Loading local model"
        case .idle:
            if modelError != nil { return "Model failed to load" }
            return isModelReady ? "Ready" : "Preparing model"
        case .recording: return "Recording"
        case .processing: return "Processing locally"
        }
    }

    var statusSymbol: String {
        if pipelineState == .idle, modelError != nil { return "exclamationmark.triangle.fill" }
        switch pipelineState {
        case .loadingModel: return "arrow.down.circle"
        case .idle: return "checkmark.circle.fill"
        case .recording: return "mic.fill"
        case .processing: return "waveform"
        }
    }

    func refreshPermissionSnapshot() {
        permissions = PermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio),
            accessibilityTrusted: AXIsProcessTrusted()
        )
    }

    func completeOnboarding() {
        settingsStore.settings.hasCompletedOnboarding = true
    }

    func toggleTestDictation() {
        if testRecordingActive {
            stopDictation()
            testRecordingActive = false
        } else {
            startDictation()
            testRecordingActive = true
        }
    }

    func openLogFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/offlinevoice.log"))
    }

    func copyDiagnostics() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let text = """
        OfflineVoice diagnostics
        Version: \(appVersion)
        Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Microphone: \(permissions.microphone.rawValue)
        Accessibility: \(permissions.accessibilityTrusted)
        Mode: \(settingsStore.settings.recognitionMode.rawValue) (\(settingsStore.settings.recognitionMode.engineName))
        Config: \(SettingsStore.fileURL.path)
        Log: /tmp/offlinevoice.log
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
