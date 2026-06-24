import AppKit

/// A floating capsule HUD near the bottom of the screen, like Wispr Flow /
/// Typeless. Shows an animated waveform while recording and a spinner while
/// transcribing. Click-through, shows on all spaces and over fullscreen apps.
@MainActor
final class IndicatorController {
    private let panel: NSPanel
    private let bars = BarsView()
    private let spinner = NSProgressIndicator()
    private let messageIcon = NSImageView()
    private let messageLabel = NSTextField(labelWithString: "No sound reached mic")
    private let messageStack = NSStackView()
    private let size = NSSize(width: 96, height: 40)
    /// Wider capsule used only for the transient "no sound" message.
    private let messageSize = NSSize(width: 230, height: 40)
    /// While true, an external `hide()` is ignored so the message survives the
    /// `.idle` state change that fires right after a near-silent capture.
    private var showingNoAudio = false
    /// Bumped on every state change to cancel a pending message auto-dismiss.
    private var noAudioToken = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        container.layer?.cornerRadius = size.height / 2
        container.autoresizingMask = [.width, .height]

        bars.frame = container.bounds
        bars.autoresizingMask = [.width, .height]
        container.addSubview(bars)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)

        // Transient "no sound" message: a mic-slash icon + short label. This is the
        // one place the HUD shows text — the failure happens while the user is
        // looking at another app, so the warning has to surface at the HUD itself,
        // not only on the Home banner they can't see.
        messageIcon.image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "No sound")
        messageIcon.contentTintColor = NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = .white
        messageStack.orientation = .horizontal
        messageStack.spacing = 6
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.addArrangedSubview(messageIcon)
        messageStack.addArrangedSubview(messageLabel)
        messageStack.isHidden = true
        container.addSubview(messageStack)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            messageStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        panel.contentView = container
    }

    func showRecording() {
        endNoAudio()
        panel.setContentSize(size)
        bars.isHidden = false
        bars.start()
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        present()
    }

    /// Feeds real mic level (0...1) into the waveform so the bars reflect actual
    /// input. A silent/busy device keeps this near 0 and the bars stay flat.
    func updateLevel(_ level: Float) {
        bars.setLevel(level)
    }

    func showProcessing() {
        endNoAudio()
        panel.setContentSize(size)
        bars.isHidden = true
        bars.stop()
        spinner.isHidden = false
        spinner.startAnimation(nil)
        present()
    }

    /// Briefly takes over the HUD to say a recording captured no audio, then hides
    /// itself. Survives the immediate `.idle` hide() via `showingNoAudio`.
    func showNoAudio() {
        bars.isHidden = true
        bars.stop()
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        messageStack.isHidden = false
        showingNoAudio = true
        noAudioToken += 1
        let token = noAudioToken
        panel.setContentSize(messageSize)
        present()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.noAudioToken == token else { return }
            self.endNoAudio()
            self.panel.orderOut(nil)
        }
    }

    func hide() {
        // Don't yank the "no sound" message off-screen the instant we return to
        // idle; its own timer dismisses it.
        if showingNoAudio { return }
        bars.stop()
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }

    private func endNoAudio() {
        showingNoAudio = false
        noAudioToken += 1
        messageStack.isHidden = true
    }

    private func present() {
        reposition()
        panel.orderFrontRegardless()
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 96
        )
        panel.setFrameOrigin(origin)
    }
}

/// Animated "listening" waveform — a row of vertical bars whose height tracks the
/// real mic level, with a travelling sine wave for liveliness. Flat bars mean no
/// signal is reaching the mic.
private final class BarsView: NSView {
    private var phase: CGFloat = 0
    private var timer: Timer?
    private let barCount = 5
    private let barWidth: CGFloat = 4
    private let gap: CGFloat = 5
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 26
    /// Most recent mic level (0...1), updated off the audio path.
    private var targetLevel: CGFloat = 0
    /// Eased level actually drawn, so the bars rise/fall smoothly.
    private var currentLevel: CGFloat = 0

    func setLevel(_ level: Float) {
        targetLevel = max(0, min(1, CGFloat(level)))
    }

    func start() {
        currentLevel = 0
        targetLevel = 0
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.35
            self.currentLevel += (self.targetLevel - self.currentLevel) * 0.3
            self.needsDisplay = true
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        targetLevel = 0
        currentLevel = 0
    }

    override func draw(_ dirtyRect: NSRect) {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        var x = bounds.midX - totalWidth / 2
        let cy = bounds.midY
        NSColor(red: 1.0, green: 0.82, blue: 0.12, alpha: 1.0).setFill()
        for i in 0..<barCount {
            // Sine gives each bar a lively offset; currentLevel scales the swing so
            // a silent capture collapses every bar to minHeight.
            let wave = abs(sin(phase + CGFloat(i) * 0.7))
            let height = minHeight + (maxHeight - minHeight) * currentLevel * (0.45 + 0.55 * wave)
            let rect = NSRect(x: x, y: cy - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + gap
        }
    }
}
