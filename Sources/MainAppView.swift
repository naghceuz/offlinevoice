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

    private let titles = ["Welcome", "Permissions", "Hotkey", "Local engine", "Ready"]

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
                    case 1: permissions
                    case 2: hotkey
                    case 3: engine
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
            }
            .padding(28)
        }
        .frame(minWidth: 860, minHeight: 600)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(48)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Allow the basics")
                .font(.largeTitle.weight(.bold))
            Text("Microphone captures your voice. Accessibility lets OfflineVoice listen for the global hotkey and paste into the active app.")
                .foregroundStyle(.secondary)
                .font(.title3)
            PermissionRow(
                title: "Microphone",
                detail: "Required for voice capture.",
                allowed: appState.permissions.microphone == .authorized,
                actionTitle: "Open Microphone Settings",
                action: appState.openMicrophoneSettings
            )
            PermissionRow(
                title: "Accessibility",
                detail: "Required for global shortcuts and auto paste.",
                allowed: appState.permissions.accessibilityTrusted,
                actionTitle: "Open Accessibility Settings",
                action: appState.openAccessibilitySettings
            )
            Button("Refresh permission status") { appState.refreshHealth() }
        }
        .padding(48)
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

    private var engine: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Local engine")
                .font(.largeTitle.weight(.bold))
            Text("Transcription runs entirely on your Mac. The default Speed mode uses a multilingual model bundled with the app: it detects Chinese, English, Japanese, Korean and Cantonese by itself — including mixed Chinese and English in one sentence.")
                .font(.title3)
                .foregroundStyle(.secondary)
            StatusPill(
                text: appState.isModelReady ? "Model ready" : "Preparing model",
                systemImage: appState.isModelReady ? "checkmark.circle.fill" : "arrow.down.circle",
                color: appState.isModelReady ? .green : Brand.yellow
            )
            Text("Want to try Whisper for English or technical speech, or Apple's own recognizer for your system language only? Switch modes any time in Speed & Accuracy.")
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
            StatusPill(text: "Audio and text stay on your Mac", systemImage: "lock.shield", color: Brand.yellow)
        }
        .padding(48)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let allowed: Bool
    let actionTitle: String
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
            Button(actionTitle, action: action)
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
