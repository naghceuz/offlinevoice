import AppKit
import AVFoundation
import SwiftUI

enum SidebarPage: String, CaseIterable, Identifiable {
    case home = "Home"
    case settings = "Settings"
    case shortcuts = "Shortcuts"
    case privacy = "Speed & Accuracy"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .settings: return "gearshape"
        case .shortcuts: return "keyboard"
        case .privacy: return "speedometer"
        case .about: return "info.circle"
        }
    }
}

struct MainAppView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var selection: SidebarPage? = .home

    var body: some View {
        Group {
            if settingsStore.settings.hasCompletedOnboarding {
                NavigationSplitView {
                    List(SidebarPage.allCases, selection: $selection) { page in
                        Label(page.rawValue, systemImage: page.symbol)
                            .tag(page)
                    }
                    .navigationSplitViewColumnWidth(min: 210, ideal: 230)
                    .safeAreaInset(edge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            BrandLockup()
                            Text("No account required")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                } detail: {
                    pageView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
            } else {
                OnboardingView()
            }
        }
    }

    @ViewBuilder
    private var pageView: some View {
        switch selection ?? .home {
        case .home: HomeView()
        case .settings: SettingsPageView()
        case .shortcuts: ShortcutsView()
        case .privacy: PrivacyLocalAIView()
        case .about: AboutView()
        }
    }
}

struct BrandLockup: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(Brand.yellow)
                .frame(width: 24, height: 24)
            Text("OfflineVoice")
                .font(.headline.weight(.bold))
        }
    }
}

enum Brand {
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.12)
    static let dark = Color(red: 0.035, green: 0.035, blue: 0.03)
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(22)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var step = 0

    private let titles = ["Welcome", "Microphone", "Accessibility", "Hotkey", "Ready"]

    private var microphoneGranted: Bool { appState.permissions.microphone == .authorized }
    private var microphoneDenied: Bool {
        appState.permissions.microphone == .denied || appState.permissions.microphone == .restricted
    }
    private var accessibilityGranted: Bool { appState.permissions.accessibilityTrusted }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BrandLockup()
                Spacer()
                Text("Setup \(step + 1) of \(titles.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(28)

            // Step content is driven entirely by the Back/Continue buttons, so a
            // plain switch avoids SwiftUI's native tab strip and keeps the look clean.
            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: microphone
                    case 2: accessibility
                    case 3: hotkey
                    default: finish
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Back") { step = max(0, step - 1) }
                    .disabled(step == 0)
                Spacer()
                Button(step == titles.count - 1 ? "Open OfflineVoice" : "Continue") {
                    if step == titles.count - 1 {
                        appState.completeOnboarding()
                    } else {
                        step += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Brand.yellow)
                // The two permission steps cannot be skipped: without them the
                // app does not work, and a "skip" is what every user would pick.
                .disabled((step == 1 && !microphoneGranted) || (step == 2 && !accessibilityGranted))
            }
            .padding(28)
        }
        .frame(minWidth: 860, minHeight: 600)
        // Each permission screen asks macOS the moment it appears, so the user
        // only ever answers the system dialog — one at a time, in order.
        .onChange(of: step) { newStep in requestForStep(newStep) }
        .onAppear { requestForStep(step) }
        // …and moves on by itself once the permission is in place, so the normal
        // path needs no clicks inside this window at all.
        .onChange(of: microphoneGranted) { granted in advance(from: 1, when: granted) }
        .onChange(of: accessibilityGranted) { granted in advance(from: 2, when: granted) }
    }

    private func requestForStep(_ s: Int) {
        switch s {
        case 1 where !microphoneGranted && !microphoneDenied: appState.requestMicrophoneAccess()
        case 2 where !accessibilityGranted: appState.requestAccessibilityAccess()
        default: break
        }
    }

    private func advance(from permissionStep: Int, when granted: Bool) {
        guard granted, step == permissionStep else { return }
        // Leave the green check on screen for a moment so the change registers.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if step == permissionStep { step += 1 }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Speak anywhere.\nType nowhere.")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .lineSpacing(-4)
            Text("OfflineVoice turns rough speech into text across your Mac. It is built for local transcription, local cleanup, and private offline use.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620, alignment: .leading)
            HStack(spacing: 12) {
                StatusPill(text: "Local ASR", systemImage: "lock.fill", color: Brand.yellow)
                StatusPill(text: "No subscription", systemImage: "nosign", color: .green)
                StatusPill(text: "Works across apps", systemImage: "rectangle.3.group", color: .blue)
            }
            Text("Next, macOS will ask for two permissions, one after the other: the microphone, then Accessibility. Both are needed; each takes one click.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(48)
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Let OfflineVoice hear you")
                .font(.largeTitle.weight(.bold))
            Text("Audio is captured only while you hold the hotkey, is transcribed on this Mac, and is never stored or uploaded. Click Allow in the macOS prompt.")
                .font(.title3)
                .foregroundStyle(.secondary)
            PermissionRow(
                title: "Microphone",
                detail: microphoneGranted ? "Voice capture is enabled."
                    : microphoneDenied ? "Microphone access was declined. Turn it on in System Settings and this screen continues by itself."
                    : "Waiting for your answer in the macOS prompt…",
                allowed: microphoneGranted,
                actionTitle: nil,
                action: {}
            )
            if microphoneDenied {
                settingsFallback(title: "Open Microphone Settings", action: appState.openMicrophoneSettings)
            }
        }
        .padding(48)
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Let it work in every app")
                .font(.largeTitle.weight(.bold))
            Text("Accessibility access lets OfflineVoice notice the hotkey while another app is in front, and paste the finished text at your cursor. In the macOS prompt choose Open System Settings, turn on OfflineVoice, then come back here.")
                .font(.title3)
                .foregroundStyle(.secondary)
            PermissionRow(
                title: "Accessibility",
                detail: accessibilityGranted ? "Global hotkey and auto-paste are enabled."
                    : "Waiting for the switch in System Settings ▸ Privacy & Security ▸ Accessibility…",
                allowed: accessibilityGranted,
                actionTitle: nil,
                action: {}
            )
            if !accessibilityGranted {
                settingsFallback(title: "Open Accessibility Settings", action: appState.openAccessibilitySettings)
            }
        }
        .padding(48)
    }

    /// Shown only when the system prompt is gone (declined or dismissed), since
    /// macOS will not show it a second time: the one remaining way forward is
    /// System Settings. Status refreshes on its own when the app comes back.
    private func settingsFallback(title: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Brand.yellow)
            Text("Closed the prompt? Open the setting directly — this screen moves on as soon as it is enabled.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var hotkey: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Use one hold-to-talk key")
                .font(.largeTitle.weight(.bold))
            Text("Default: hold \(settingsStore.settings.primaryShortcut.displayName), speak, then release to paste.")
                .font(.title3)
                .foregroundStyle(.secondary)
            ShortcutRecorderView(shortcut: Binding(
                get: { settingsStore.settings.primaryShortcut },
                set: { settingsStore.settings.primaryShortcut = $0 }
            ))
            Text("Pick the modifier key you want to hold while talking. More key combinations are coming in a later version.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(48)
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Try it anywhere")
                .font(.largeTitle.weight(.bold))
            Text("Open any text field, hold \(settingsStore.settings.primaryShortcut.displayName), speak, and release. The finished text is pasted into the focused app.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Transcription runs entirely on your Mac with a multilingual model bundled in the app: it detects Chinese, English, Japanese, Korean and Cantonese by itself, mixed Chinese and English included. Whisper and Apple's own recognizer are available in Speed & Accuracy.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                StatusPill(
                    text: appState.isModelReady ? "Model ready" : "Preparing model",
                    systemImage: appState.isModelReady ? "checkmark.circle.fill" : "arrow.down.circle",
                    color: appState.isModelReady ? .green : Brand.yellow
                )
                StatusPill(text: "Audio and text stay on your Mac", systemImage: "lock.shield", color: Brand.yellow)
            }
        }
        .padding(48)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let allowed: Bool
    /// nil hides the trailing button (the onboarding screens put one primary
    /// action under the row instead of a small button inside it).
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(allowed ? .green : Brand.yellow)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
