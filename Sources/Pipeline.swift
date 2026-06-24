import AppKit
import ApplicationServices
import Foundation

/// Orchestrates the dictation loop: record → transcribe → clean → paste.
@MainActor
final class Pipeline {
    enum State { case loadingModel, idle, recording, processing }

    var onStateChange: (State) -> Void = { _ in }
    var onModelReadyChange: (Bool) -> Void = { _ in }
    /// Reports a model load/prepare failure (nil = cleared / loaded fine).
    var onModelLoadFailed: (String?) -> Void = { _ in }
    /// Fired when a finished dictation couldn't be auto-pasted because
    /// Accessibility isn't trusted — the text is left on the clipboard instead.
    var onPasteNeedsAccessibility: () -> Void = { }
    /// Real-time mic level (0...1) during recording, for the waveform HUD.
    var onAudioLevel: (Float) -> Void = { _ in }
    /// Fired after a recording finishes: `true` when the capture was near-silent
    /// (likely a wrong/busy input device), `false` to clear a prior warning.
    var onAudioInputWarning: (Bool) -> Void = { _ in }
    private(set) var isModelReady = false
    private(set) var state: State = .idle

    private let recorder = AudioRecorder()
    private var asr: ASREngine
    private let settingsStore: SettingsStore
    /// Signature of the ASR-relevant settings backing the current `asr` instance.
    private var engineSignature: String
    /// Set when a reload is requested mid-recording/processing; applied on idle.
    private var pendingReload = false
    /// Audio captured while the model was still loading, held until the model
    /// becomes ready so a dictation started during the cold-start window isn't
    /// dropped — it transcribes as soon as prewarm finishes.
    private var pendingSamples: [Float]?

    /// Minimum samples worth processing (~0.2s at 16 kHz) to ignore accidental taps.
    private let minSamples = 3_200
    /// Below this peak amplitude a capture is treated as effectively silent —
    /// real speech sits well above it, a dead/busy device sits at ~0.
    private let silenceThreshold: Float = 0.01

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.asr = settingsStore.settings.asConfig().makeASREngine()
        self.engineSignature = Self.signature(for: settingsStore.settings)
        // Forward real mic level to the HUD. The tap fires on the audio thread, so
        // hop to main where the (MainActor) callback updates UI.
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.onAudioLevel(level) }
        }
    }

    /// ASR-relevant settings that require rebuilding the engine when changed.
    static func signature(for settings: AppSettings) -> String {
        settings.recognitionMode.rawValue
    }

    /// Rebuilds the ASR engine from current settings and re-prewarms, so engine
    /// or model changes take effect without restarting the app. A reload during
    /// recording/processing is deferred until the pipeline returns to idle.
    func reloadEngineIfNeeded() {
        let newSignature = Self.signature(for: settingsStore.settings)
        guard newSignature != engineSignature else { return }
        engineSignature = newSignature
        guard state == .idle else {
            pendingReload = true
            Log.write("ASR reload requested while busy, deferring to idle")
            return
        }
        performReload()
    }

    private func performReload() {
        asr = settingsStore.settings.asConfig().makeASREngine()
        isModelReady = false
        onModelReadyChange(false)
        Log.write("ASR engine reloaded (\(engineSignature)), prewarming new model")
        prewarm()
    }

    /// Single funnel for state changes so deferred reloads can fire on idle.
    private func transition(to newState: State) {
        state = newState
        onStateChange(newState)
        if newState == .idle, pendingReload {
            pendingReload = false
            performReload()
        }
    }

    /// Loads the transcription model in the background so the first dictation
    /// doesn't pay the download/load cost.
    func prewarm() {
        transition(to: .loadingModel)
        Task {
            do {
                try await asr.prepare()
                isModelReady = true
                onModelReadyChange(true)
                onModelLoadFailed(nil)
                Log.write("prewarm done, model ready")
            } catch {
                Log.write("model prewarm failed: \(error)")
                isModelReady = false
                onModelReadyChange(false)
                onModelLoadFailed("Local model failed to load. Open the log for details, then retry.")
                // Can't transcribe what we queued — drop it so we don't hang in
                // .processing forever, and let the retry path reload the model.
                if pendingSamples != nil {
                    pendingSamples = nil
                    Log.write("dropped queued recording: model failed to load")
                }
            }
            // A dictation captured during the load window waits in .processing —
            // now that the model is ready, transcribe it. If the user is still
            // holding the key (mid-recording), don't interrupt: finish() will
            // transcribe on release since isModelReady is now true.
            if let queued = pendingSamples {
                pendingSamples = nil
                Log.write("flushing queued recording, samples=\(queued.count)")
                transcribeAndPaste(queued)
            } else if state != .recording {
                transition(to: .idle)
            }
        }
    }

    func startRecording() {
        // Allow starting from idle OR while the model is still loading — capturing
        // audio doesn't need the model, and queuing the result (see finish()) hides
        // the cold-start wait behind the user's own speech. Only reject when a
        // recording/processing is already in flight, which would orphan a capture.
        guard state == .idle || state == .loadingModel else {
            Log.write("startRecording ignored, state=\(state)")
            return
        }
        do {
            try recorder.start(preferredDeviceUID: settingsStore.settings.preferredInputDeviceUID)
            Log.write("recording started (modelReady=\(isModelReady))")
            transition(to: .recording)
        } catch {
            Log.write("failed to start recording: \(error)")
            // Fall back to whichever resting state we came from.
            transition(to: isModelReady ? .idle : .loadingModel)
        }
    }

    func finish() {
        // Ignore stray releases / double finishes; only a live recording can finish.
        guard state == .recording else {
            Log.write("finish ignored, state=\(state)")
            return
        }
        let samples = recorder.stop()
        Log.write("recording stopped, samples=\(samples.count) (min=\(minSamples))")
        guard samples.count >= minSamples else {
            Log.write("too few samples, ignoring")
            // Return to whichever resting state matches model readiness.
            transition(to: isModelReady ? .idle : .loadingModel)
            return
        }
        // The user spoke long enough, so a near-silent capture means audio never
        // reached us — a wrong/busy input device. Warn; otherwise clear any prior
        // warning now that capture works.
        let nearSilent = recorder.lastPeak < silenceThreshold
        onAudioInputWarning(nearSilent)
        guard !nearSilent else {
            // Critical: never transcribe silence. Whisper-family models hallucinate
            // confident phrases ("Thank you.", "Thank you for watching") on silent
            // input, which would then auto-paste garbage. Drop it and just warn.
            Log.write("near-silent capture peak=\(recorder.lastPeak), skipping transcription")
            transition(to: isModelReady ? .idle : .loadingModel)
            return
        }
        transition(to: .processing)

        guard isModelReady else {
            // Captured during the cold-start window: hold the audio and stay in
            // .processing (spinner). prewarm()'s completion flushes it.
            pendingSamples = samples
            Log.write("queued recording, awaiting model")
            return
        }
        transcribeAndPaste(samples)
    }

    /// Transcribes captured audio and pastes the result, returning to idle when
    /// done. Shared by the normal path (finish with model ready) and the deferred
    /// path (prewarm flushing audio captured during the load window).
    private func transcribeAndPaste(_ samples: [Float]) {
        // Our menu-bar app never takes focus, so the frontmost app is whatever
        // the user was dictating into.
        let currentSettings = settingsStore.settings

        let engine = asr
        Task {
            defer { transition(to: .idle) }
            do {
                let raw = try await engine.transcribe(samples)
                // Privacy: never log the transcript itself, only its length.
                Log.write("transcribed chars=\(raw.count)")
                guard !raw.isEmpty else { Log.write("empty transcription, nothing to paste"); return }
                // No post-processing: the engine already returns paste-ready,
                // punctuated text. Keeping dictation instant is the whole point.
                let final = raw
                if currentSettings.autoPaste, !AXIsProcessTrusted() {
                    // Without Accessibility the synthetic ⌘V is silently dropped by
                    // the system. Don't pretend it worked: leave the text on the
                    // clipboard (no restore) so ⌘V works manually, and surface it.
                    Paster.insert(final, autoPaste: false, restoreClipboard: false)
                    Log.write("paste blocked: accessibility not trusted; text left on clipboard")
                    onPasteNeedsAccessibility()
                } else {
                    Log.write("pasting chars=\(final.count)")
                    Paster.insert(
                        final,
                        autoPaste: currentSettings.autoPaste,
                        restoreClipboard: currentSettings.restoreClipboard
                    )
                }
            } catch {
                Log.write("pipeline error: \(error)")
            }
        }
    }
}
