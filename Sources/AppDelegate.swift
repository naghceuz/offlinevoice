import AppKit
import AVFoundation
import ApplicationServices
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let settingsStore = SettingsStore()
    private lazy var appState = AppState(settingsStore: settingsStore)
    private let hotkey = HotkeyMonitor()
    private let indicator = IndicatorController()
    private var pipeline: Pipeline!
    private var mainWindow: NSWindow?
    private var healthTimer: Timer?
    private var didPromptAccessibilityForPaste = false
    private var cancellables = Set<AnyCancellable>()

    private enum Tag: Int { case status = 1, shortcut = 2, accessibility = 3, mic = 4 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        pipeline = Pipeline(settingsStore: settingsStore)
        pipeline.onStateChange = { [weak self] state in
            self?.appState.pipelineState = state
            if state != .recording {
                self?.appState.testRecordingActive = false
            }
            self?.render(state)
        }
        pipeline.onModelReadyChange = { [weak self] ready in
            self?.appState.isModelReady = ready
            self?.render(self?.appState.pipelineState ?? .idle)
        }
        pipeline.onModelLoadFailed = { [weak self] message in
            self?.appState.modelError = message
            self?.render(self?.appState.pipelineState ?? .idle)
        }
        pipeline.onPasteNeedsAccessibility = { [weak self] in
            self?.handlePasteNeedsAccessibility()
        }
        pipeline.onAudioLevel = { [weak self] level in
            self?.indicator.updateLevel(level)
        }
        pipeline.onAudioInputWarning = { [weak self] lowSignal in
            guard let self else { return }
            self.appState.audioInputWarning = lowSignal
                ? "No sound reached the mic. Your input device may be busy on another device (e.g. AirPods connected to your phone). Pick the built‑in mic in Settings, or check your system input."
                : nil
            // Surface it on the floating HUD too — the user is looking at the app
            // they dictated into, not the Home banner.
            if lowSignal { self.indicator.showNoAudio() }
        }

        appState.openAccessibilitySettings = { [weak self] in self?.openAccessibilitySettings() }
        appState.openMicrophoneSettings = { [weak self] in self?.openMicSettings() }
        appState.startDictation = { [weak self] in self?.pipeline.startRecording() }
        appState.stopDictation = { [weak self] in self?.pipeline.finish() }
        appState.refreshHealth = { [weak self] in self?.refreshHealth() }
        appState.retryModelLoad = { [weak self] in
            self?.appState.modelError = nil
            self?.pipeline.prewarm()
        }
        appState.runBenchmark = { Benchmark.run() }

        hotkey.shortcut = settingsStore.settings.primaryShortcut
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            // Acknowledge the keypress *instantly*. The audio engine cold-starts
            // in 70–550 ms and `render(.recording)` only fires after it succeeds,
            // so the HUD used to lag behind the press and the user assumed it
            // missed. We now capture audio even while the model loads (finish()
            // queues it), so show the recording waveform the moment the key drops.
            self.indicator.showRecording()
            self.pipeline.startRecording()
        }
        hotkey.onRelease = { [weak self] in
            self?.pipeline.finish()
        }

        bindSettings()
        settingsStore.refreshLaunchAtLoginStatus()
        updateStatusItemVisibility()
        render(.idle)

        Log.write("launch: ax=\(AXIsProcessTrusted()) micStatus=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        requestMicAccess()
        requestAccessibilityIfNeeded()
        hotkey.start()
        Log.write("hotkey monitor started shortcut=\(settingsStore.settings.primaryShortcut.displayName)")
        pipeline.prewarm()

        refreshHealth()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHealth()
            }
        }

        showMainWindow()

        // Headless dev run: `open -a OfflineVoice --args --benchmark`.
        if CommandLine.arguments.contains("--benchmark") {
            Log.write("launch: --benchmark flag present")
            Benchmark.run()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func bindSettings() {
        settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                guard let self else { return }
                self.hotkey.shortcut = settings.primaryShortcut
                self.updateStatusItemVisibility()
                self.pipeline?.reloadEngineIfNeeded()
                self.render(self.appState.pipelineState)
            }
            .store(in: &cancellables)
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let root = MainAppView()
                .environmentObject(appState)
                .environmentObject(settingsStore)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "OfflineVoice"
            window.setContentSize(NSSize(width: 960, height: 680))
            window.minSize = NSSize(width: 860, height: 600)
            window.isReleasedWhenClosed = false
            window.center()
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusItemVisibility() {
        if settingsStore.settings.showMenuBarIcon {
            if statusItem == nil {
                setupStatusItem()
            }
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open OfflineVoice", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(makeLabel(.status, "Ready"))
        menu.addItem(makeLabel(.shortcut, "Hold Right Option to dictate"))
        menu.addItem(.separator())

        let accessibility = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibility.tag = Tag.accessibility.rawValue
        accessibility.target = self
        menu.addItem(accessibility)

        let mic = NSMenuItem(title: "", action: #selector(openMicSettings), keyEquivalent: "")
        mic.tag = Tag.mic.rawValue
        mic.target = self
        menu.addItem(mic)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit OfflineVoice", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func makeLabel(_ tag: Tag, _ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.tag = tag.rawValue
        item.isEnabled = false
        return item
    }

    private func render(_ state: Pipeline.State) {
        let (symbol, status): (String, String)
        switch state {
        case .loadingModel: (symbol, status) = ("arrow.down.circle", "Loading local model")
        case .idle:
            if appState.modelError != nil {
                (symbol, status) = ("exclamationmark.triangle", "Model failed — open OfflineVoice")
            } else if !appState.isModelReady {
                (symbol, status) = ("arrow.down.circle", "Preparing model")
            } else {
                (symbol, status) = ("mic", "Ready")
            }
        case .recording:    (symbol, status) = ("mic.fill", "Recording")
        case .processing:   (symbol, status) = ("waveform", "Processing locally")
        }

        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: symbol, accessibilityDescription: status)
            button.image?.isTemplate = true
            button.contentTintColor = (state == .recording) ? .systemYellow : nil
        }
        statusItem?.menu?.item(withTag: Tag.status.rawValue)?.title = status
        statusItem?.menu?.item(withTag: Tag.shortcut.rawValue)?.title =
            "Hold \(settingsStore.settings.primaryShortcut.displayName) to dictate"

        switch state {
        case .recording:  indicator.showRecording()
        case .processing: indicator.showProcessing()
        case .idle, .loadingModel: indicator.hide()
        }
    }

    private func requestMicAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Log.write("mic requestAccess returned granted=\(granted)")
            DispatchQueue.main.async { self?.refreshHealth() }
        }
    }

    @discardableResult
    private func requestAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func handlePasteNeedsAccessibility() {
        appState.pasteBlockedByAccessibility = true
        refreshHealth()
        // Nudge + raise the window once per launch so the user understands why
        // nothing got pasted; after that we keep copying to the clipboard quietly.
        guard !didPromptAccessibilityForPaste else { return }
        didPromptAccessibilityForPaste = true
        _ = requestAccessibilityIfNeeded()
        showMainWindow()
    }

    private func refreshHealth() {
        appState.refreshPermissionSnapshot()
        let axTrusted = AXIsProcessTrusted()
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if axTrusted { appState.pasteBlockedByAccessibility = false }

        statusItem?.menu?.item(withTag: Tag.accessibility.rawValue)?.title =
            axTrusted ? "Accessibility allowed" : "Accessibility needed..."
        statusItem?.menu?.item(withTag: Tag.mic.rawValue)?.title =
            micGranted ? "Microphone allowed" : "Microphone needed..."
    }

    @objc private func openMainWindow() {
        showMainWindow()
    }

    @objc private func openAccessibilitySettings() {
        if requestAccessibilityIfNeeded() { return }
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openMicSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
