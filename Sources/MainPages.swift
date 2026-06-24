import AppKit
import AVFoundation
import SwiftUI

struct PageShell<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(32)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        PageShell(
            title: "Home",
            subtitle: "Local voice input for any text field on your Mac."
        ) {
            if !appState.permissions.accessibilityTrusted {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auto‑paste is off until you grant Accessibility")
                            .font(.headline)
                        Text("Dictation still works — your finished text is copied to the clipboard, so press ⌘V to paste it. Grant Accessibility to have OfflineVoice paste automatically.")
                            .foregroundStyle(.secondary)
                        Button("Open Accessibility Settings", action: appState.openAccessibilitySettings)
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.yellow)
                            .padding(.top, 4)
                    }
                    Spacer()
                }
                .padding(18)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            SectionCard("Current status") {
                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: appState.statusSymbol)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(appState.statusText)
                            .font(.title2.weight(.semibold))
                        Text("Hold \(settingsStore.settings.primaryShortcut.displayName), speak, then release.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(appState.testRecordingActive ? "Stop test dictation" : "Start test dictation") {
                        appState.toggleTestDictation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.yellow)
                    .disabled(appState.modelError != nil || !appState.isModelReady)
                }

                if let modelError = appState.modelError {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(modelError)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open logs", action: appState.openLogFile)
                        Button("Retry", action: appState.retryModelLoad)
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.yellow)
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let warning = appState.audioInputWarning {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(warning)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Mic Settings", action: appState.openMicrophoneSettings)
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.yellow)
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            SectionCard("Permissions", subtitle: "OfflineVoice needs macOS permission for voice capture and app-wide paste.") {
                VStack(spacing: 12) {
                    PermissionRow(
                        title: "Microphone",
                        detail: microphoneDetail,
                        allowed: appState.permissions.microphone == .authorized,
                        actionTitle: "Open Settings",
                        action: appState.openMicrophoneSettings
                    )
                    PermissionRow(
                        title: "Accessibility",
                        detail: appState.permissions.accessibilityTrusted ? "Global shortcut and auto paste are enabled." : "Enable OfflineVoice to use the hotkey outside this window.",
                        allowed: appState.permissions.accessibilityTrusted,
                        actionTitle: "Open Settings",
                        action: appState.openAccessibilitySettings
                    )
                    HStack {
                        Label("Input Monitoring", systemImage: "keyboard")
                        Spacer()
                        Text("Not required by current v0.2 pipeline")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SectionCard("Local privacy") {
                HStack(spacing: 14) {
                    StatusPill(text: "Audio stays local", systemImage: "lock.shield", color: Brand.yellow)
                    StatusPill(text: "No account", systemImage: "person.crop.circle.badge.xmark", color: .blue)
                    StatusPill(text: "No subscription", systemImage: "nosign", color: .green)
                }
                Text("Transcription runs entirely on this Mac. OfflineVoice does not upload audio or train on your text.")
                    .foregroundStyle(.secondary)
            }

            SectionCard("Quick actions") {
                HStack(spacing: 12) {
                    Button("Open Accessibility Settings", action: appState.openAccessibilitySettings)
                    Button("Open logs", action: appState.openLogFile)
                    Button("Refresh status", action: appState.refreshHealth)
                }
            }
        }
    }

    private var statusColor: Color {
        if appState.modelError != nil { return .orange }
        switch appState.pipelineState {
        case .recording, .processing:
            return Brand.yellow
        case .loadingModel:
            return .blue
        case .idle:
            return (appState.permissions.microphone == .authorized && appState.permissions.accessibilityTrusted) ? .green : Brand.yellow
        }
    }

    private var microphoneDetail: String {
        switch appState.permissions.microphone {
        case .authorized:
            return "Voice capture is enabled."
        case .denied, .restricted:
            return "Enable microphone access in System Settings."
        case .notDetermined:
            return "macOS will ask the first time OfflineVoice records."
        @unknown default:
            return "Permission status is unknown."
        }
    }
}

struct SettingsPageView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        PageShell(
            title: "Settings",
            subtitle: "Tune the core dictation behavior."
        ) {
            SectionCard("Dictation hotkey", subtitle: "Modifier-only shortcuts work best for hold-to-talk.") {
                ShortcutRecorderView(shortcut: binding(\.primaryShortcut))
            }

            SectionCard("Microphone", subtitle: "Choose which input OfflineVoice records from. System default follows macOS.") {
                Picker("Input device", selection: binding(\.preferredInputDeviceUID)) {
                    Text("System default").tag(String?.none)
                    ForEach(AudioDevices.inputDevices()) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                }
                .pickerStyle(.menu)
                Text("If a recording comes through silent, your system default may be a Bluetooth headset that's busy on another device — pick the built‑in mic here to be sure.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SectionCard("Paste behavior") {
                Toggle("Auto paste into the focused app", isOn: binding(\.autoPaste))
                Toggle("Restore clipboard after paste", isOn: binding(\.restoreClipboard))
                Text("When auto paste is off, the final dictation is copied to the clipboard only.")
                    .foregroundStyle(.secondary)
            }

            SectionCard("App behavior") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settingsStore.settings.launchAtLogin },
                    set: { settingsStore.setLaunchAtLogin($0) }
                ))
                if let notice = settingsStore.launchAtLoginNotice {
                    Text(notice)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Toggle("Show menu bar icon", isOn: binding(\.showMenuBarIcon))
                Text("The Dock app stays available even when the menu bar icon is hidden.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }
}

struct ShortcutsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        PageShell(
            title: "Shortcuts",
            subtitle: "Keep the active dictation shortcut visible and editable."
        ) {
            ShortcutModeCard(
                title: "Dictate",
                detail: "Hold to start and release to paste.",
                enabled: true
            ) {
                ShortcutRecorderView(shortcut: Binding(
                    get: { settingsStore.settings.primaryShortcut },
                    set: { settingsStore.settings.primaryShortcut = $0 }
                ))
            }

            ShortcutModeCard(
                title: "Translate",
                detail: "Future local LLM mode. Disabled in v0.2.",
                enabled: false
            ) {
                EmptyView()
            }

            ShortcutModeCard(
                title: "Ask anything",
                detail: "Future local assistant mode. Disabled in v0.2.",
                enabled: false
            ) {
                EmptyView()
            }
        }
    }
}

struct ShortcutModeCard<Content: View>: View {
    let title: String
    let detail: String
    let enabled: Bool
    @ViewBuilder var content: Content

    var body: some View {
        SectionCard(title) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "clock")
                    .font(.title2)
                    .foregroundStyle(enabled ? .green : .secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Text(detail)
                        .foregroundStyle(.secondary)
                    content
                }
                Spacer()
            }
            .opacity(enabled ? 1 : 0.62)
        }
    }
}

struct PrivacyLocalAIView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        PageShell(
            title: "Speed & Accuracy",
            subtitle: "Choose how OfflineVoice turns speech into text. Everything runs on this Mac."
        ) {
            SectionCard(
                "Recognition mode",
                subtitle: "Faster modes feel instant. Slower modes recognize English and technical speech more accurately."
            ) {
                VStack(spacing: 12) {
                    ForEach(RecognitionMode.allCases) { mode in
                        ModeCard(
                            mode: mode,
                            isSelected: settingsStore.settings.recognitionMode == mode
                        ) {
                            settingsStore.settings.recognitionMode = mode
                        }
                    }
                }
                Text("Switching modes reloads the engine locally — the next dictation waits a moment for the new model to finish loading.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SectionCard("Data handling") {
                Text("OfflineVoice does not upload your audio, does not sync transcripts, and does not train on your data. Model files are cached locally after first download.")
                    .foregroundStyle(.secondary)
                StatusPill(text: "Offline after model cache", systemImage: "wifi.slash", color: Brand.yellow)
            }

            #if DEBUG
            SectionCard(
                "Engine benchmark (dev)",
                subtitle: "Loads each model × encoder-compute combo and measures load/inference/memory/quality. Results append to /tmp/offlinevoice-benchmark.md."
            ) {
                Button("Run engine benchmark") { appState.runBenchmark() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.yellow)
                Text("Runs in the background and takes a few minutes — watch /tmp/offlinevoice.log for progress.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
    }
}

/// A single, tappable recognition-mode option. Shows the latency cost up front
/// so the speed/accuracy trade-off is explicit, not hidden behind model names.
struct ModeCard: View {
    let mode: RecognitionMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Brand.yellow : .secondary)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(mode.title)
                            .font(.headline)
                        Text(mode.latencyNote)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Brand.yellow.opacity(0.16))
                            .clipShape(Capsule())
                    }
                    Text(mode.summary)
                        .foregroundStyle(.secondary)
                    Text("Engine: \(mode.engineName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Brand.yellow.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Brand.yellow : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AboutView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageShell(
            title: "About",
            subtitle: "OfflineVoice — preview build."
        ) {
            SectionCard("Version") {
                InfoRow("Version", value: appVersion)
                InfoRow("Build", value: buildVersion)
                InfoRow("Status", value: "Signed & notarized by Apple")
            }

            SectionCard("Links") {
                HStack(spacing: 12) {
                    Link("Website", destination: URL(string: "https://www.offlinevoice.ai")!)
                    Link("Release notes", destination: URL(string: "https://www.offlinevoice.ai/#faq")!)
                    Link("Privacy policy", destination: URL(string: "https://www.offlinevoice.ai/#privacy-policy")!)
                }
            }

            SectionCard("Diagnostics") {
                HStack(spacing: 12) {
                    Button("Open log file", action: appState.openLogFile)
                    Button("Copy environment info", action: appState.copyDiagnostics)
                    Button("Open config folder") {
                        NSWorkspace.shared.open(SettingsStore.fileURL.deletingLastPathComponent())
                    }
                }
                Text("This build is signed with a Developer ID certificate and notarized by Apple, so it opens without a Gatekeeper warning.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }

    private var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Preview"
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospaced())
        }
    }
}
