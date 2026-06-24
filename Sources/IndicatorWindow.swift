import AppKit

/// A floating capsule HUD near the bottom of the screen, like Wispr Flow /
/// Typeless. Shows an animated waveform while recording and a spinner while
/// transcribing. Click-through, shows on all spaces and over fullscreen apps.
@MainActor
final class IndicatorController {
    private let panel: NSPanel
    private let bars = BarsView()
    private let spinner = NSProgressIndicator()
    private let size = NSSize(width: 96, height: 40)

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

        bars.frame = container.bounds
        bars.autoresizingMask = [.width, .height]
        container.addSubview(bars)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)

        // No text in the HUD — just the waveform (recording) or spinner
        // (processing), so nothing language-specific ever shows.
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        panel.contentView = container
    }

    func showRecording() {
        bars.isHidden = false
        bars.start()
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        present()
    }

    func showProcessing() {
        bars.isHidden = true
        bars.stop()
        spinner.isHidden = false
        spinner.startAnimation(nil)
        present()
    }

    func hide() {
        bars.stop()
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }

    private func present() {
        reposition()
        panel.orderFrontRegardless()
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 96
        )
        panel.setFrameOrigin(origin)
    }
}

/// Animated "listening" waveform — a row of vertical bars pulsing with a
/// travelling sine wave.
private final class BarsView: NSView {
    private var phase: CGFloat = 0
    private var timer: Timer?
    private let barCount = 5
    private let barWidth: CGFloat = 4
    private let gap: CGFloat = 5

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.35
            self.needsDisplay = true
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        var x = bounds.midX - totalWidth / 2
        let cy = bounds.midY
        NSColor(red: 1.0, green: 0.82, blue: 0.12, alpha: 1.0).setFill()
        for i in 0..<barCount {
            let amplitude = abs(sin(phase + CGFloat(i) * 0.7))
            let height = 7 + 15 * amplitude
            let rect = NSRect(x: x, y: cy - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + gap
        }
    }
}
