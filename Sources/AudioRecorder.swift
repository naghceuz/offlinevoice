import AVFoundation
#if os(macOS)
import AudioToolbox
#endif

/// Captures microphone audio and resamples it to 16 kHz mono Float — the
/// format the speech engines expect.
///
/// Latency design, in two layers:
///
/// 1. Everything that can be done ahead of a key press is done in `prepare()`
///    — pin the device, build the resampler, install the tap, initialize the
///    engine graph. `start()` then only starts the I/O.
/// 2. Measured on a Studio Display microphone, starting the I/O itself still
///    costs ~470 ms (the built-in mic: ~20 ms), so the first word of a
///    dictation went missing whenever the user talked on the key press. The
///    fix is to not stop the I/O right away: after a capture ends the engine
///    keeps running for `lingerSeconds`, discarding audio except for a short
///    pre-roll ring buffer. A press inside that window captures instantly and
///    even includes the ~half second spoken just before the key went down.
///    Once the window passes the engine stops, so an idle app shows no
///    microphone-in-use indicator. The first press after idle still pays the
///    device start; the HUD shows a glyph until audio really arrives.
final class AudioRecorder {
    /// How long the microphone stays open after a capture ends. Long enough to
    /// cover the pause between consecutive sentences, short enough that the
    /// system's mic indicator goes away when the user has clearly moved on.
    var lingerSeconds: TimeInterval = 10

    /// Audio kept from just before the key press (16 kHz samples).
    private let prerollCapacity = 8_000 // 0.5 s
    private var preroll: [Float] = []
    private var lingerWork: DispatchWorkItem?
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let lock = NSLock()
    private var samples: [Float] = []
    /// The tap stays installed between dictations; this gates whether its
    /// buffers are kept. Read on the audio thread, written on the caller's.
    private var isCapturing = false
    /// First buffer of the current capture already reported (for `onCaptureBegan`).
    private var reportedFirstBuffer = false

    /// Which device the engine is currently prepared for (nil = system default)
    /// and whether something invalidated that preparation (device change,
    /// configuration change notification, a failed start).
    private var preparedDeviceUID: String?
    private var isPrepared = false
    private var configObserver: NSObjectProtocol?

    /// Per-buffer input level (0...1 peak) reported while recording so the UI can
    /// reflect *real* mic activity. Fires on the audio thread — hop to main before
    /// touching UI.
    var onLevel: ((Float) -> Void)?

    /// Fires once per capture, on the audio thread, when the first buffer of
    /// audio actually arrives — i.e. the microphone is really open. The HUD
    /// switches to the recording waveform on this, not on the key press, so the
    /// user starts talking when audio is flowing rather than half a second early.
    var onCaptureBegan: (() -> Void)?

    /// Peak amplitude of the most recent completed capture (set by `stop()`).
    /// Used to tell a real recording from a near-silent one (wrong/busy device).
    private(set) var lastPeak: Float = 0

    init() {
        // Default input device changed, display with a mic plugged/unplugged,
        // sample rate changed… the graph must be rebuilt before the next start.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// AVAudioEngine stops rendering when the input device changes under it
    /// (display unplugged, default input switched, sample rate changed). If a
    /// capture is in progress the engine must be rebuilt and restarted *now*,
    /// or the rest of the capture is silence; otherwise just drop the stale
    /// preparation and end any linger, so the next press rebuilds the graph.
    private func handleConfigurationChange() {
        let (capturing, device) = lock.withLock { (isCapturing, preparedDeviceUID) }
        lock.withLock { isPrepared = false }
        if capturing {
            Log.write("AudioRecorder: input configuration changed mid-capture, restarting engine")
            do {
                try prepare(preferredDeviceUID: device)
                lock.withLock { isCapturing = true }
                try engine.start()
            } catch {
                Log.write("AudioRecorder: restart after configuration change failed: \(error)")
            }
        } else {
            Log.write("AudioRecorder: input configuration changed, will re-prepare on next press")
            lingerWork?.cancel()
            lingerWork = nil
            if engine.isRunning { engine.stop() }
            lock.withLock { preroll.removeAll(keepingCapacity: true) }
        }
    }

    // MARK: - Prepare

    /// Does all the slow, device-dependent setup so a later `start()` is cheap.
    /// Safe to call repeatedly; a no-op when already prepared for `preferredDeviceUID`.
    func prepare(preferredDeviceUID: String? = nil) throws {
        let alreadyPrepared = lock.withLock { isPrepared && preparedDeviceUID == preferredDeviceUID }
        if alreadyPrepared { return }

        let t0 = CFAbsoluteTimeGetCurrent()
        func ms(since t: CFAbsoluteTime) -> Int { Int((CFAbsoluteTimeGetCurrent() - t) * 1000) }

        // Tear down any previous preparation (device may have changed).
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()

        // iOS requires an active, record-capable audio session before the engine's
        // input node has a usable format; macOS has no AVAudioSession.
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: [])
        #endif

        let input = engine.inputNode

        // Pin the input to the user's chosen device *before* reading its format, so
        // dictation isn't at the mercy of whatever macOS picked as default (e.g. an
        // AirPods mic that's busy on a phone). Best-effort: fall back to default.
        let tPin = CFAbsoluteTimeGetCurrent()
        #if os(macOS)
        if let uid = preferredDeviceUID, let deviceID = AudioDevices.deviceID(forUID: uid) {
            if let unit = input.audioUnit {
                var dev = deviceID
                let status = AudioUnitSetProperty(
                    unit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &dev,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if status != noErr {
                    Log.write("AudioRecorder: couldn't pin input device \(uid) (err=\(status)), using default")
                }
            }
        } else if preferredDeviceUID != nil {
            Log.write("AudioRecorder: preferred input device not connected, using default")
        }
        #endif
        let pinMs = ms(since: tPin)

        let tConv = CFAbsoluteTimeGetCurrent()
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            // Some uncommon mic formats can't be resampled to 16 kHz mono; surface
            // it instead of silently recording nothing.
            Log.write("AudioRecorder: no converter for input format \(inputFormat)")
            throw NSError(
                domain: "OfflineVoice.AudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This microphone's audio format is not supported."]
            )
        }
        self.converter = converter
        let convMs = ms(since: tConv)

        let tTap = CFAbsoluteTimeGetCurrent()
        // Small buffers so the first audio lands ~20 ms after I/O starts rather
        // than ~85 ms; the resampler cost per buffer is negligible.
        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        let tapMs = ms(since: tTap)

        let tPrep = CFAbsoluteTimeGetCurrent()
        engine.prepare()
        let prepMs = ms(since: tPrep)

        lock.withLock {
            isPrepared = true
            preparedDeviceUID = preferredDeviceUID
        }
        Log.write("AudioRecorder: prepared in \(ms(since: t0)) ms (pin=\(pinMs) converter=\(convMs) tap=\(tapMs) prepare=\(prepMs)) rate=\(Int(inputFormat.sampleRate))")
    }

    // MARK: - Start / stop

    /// Starts capture. Cheap when `prepare()` already ran for this device;
    /// otherwise prepares first (the old cold path).
    func start(preferredDeviceUID: String? = nil) throws {
        lingerWork?.cancel()
        lingerWork = nil

        let prepared = lock.withLock { isPrepared && preparedDeviceUID == preferredDeviceUID }
        if engine.isRunning, prepared {
            // Warm path: still running from the previous capture. Begin with the
            // pre-roll so speech that started before the key press is kept.
            let prerollCount: Int = lock.withLock {
                samples.removeAll(keepingCapacity: true)
                samples.append(contentsOf: preroll)
                preroll.removeAll(keepingCapacity: true)
                reportedFirstBuffer = true
                isCapturing = true
                return samples.count
            }
            Log.write("AudioRecorder: warm start, preroll=\(prerollCount) samples")
            onCaptureBegan?()
            return
        }

        if engine.isRunning { engine.stop() }
        try prepare(preferredDeviceUID: preferredDeviceUID)

        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            preroll.removeAll(keepingCapacity: true)
            reportedFirstBuffer = false
            isCapturing = true
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            try engine.start()
        } catch {
            // A failed start usually means the prepared graph is stale (device
            // went away). Drop the preparation so the next attempt rebuilds it.
            lock.withLock { isCapturing = false; isPrepared = false }
            throw error
        }
        Log.write("AudioRecorder: cold start=\(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms")
    }

    /// Ends the capture and returns the resampled mono samples. The engine keeps
    /// running for `lingerSeconds` (feeding the pre-roll), then stops.
    func stop() -> [Float] {
        lock.withLock {
            isCapturing = false
            preroll.removeAll(keepingCapacity: true)
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine.stop()
            self.lock.withLock { self.preroll.removeAll(keepingCapacity: true) }
            // Keep the graph allocated so the next cold start skips prepare().
            self.engine.prepare()
            Log.write("AudioRecorder: linger over, mic closed")
        }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lingerSeconds, execute: work)
        // Release the session on iOS so other apps regain audio; harmless no-op
        // elsewhere. Failure here must not lose the capture, so it's best-effort.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
        let captured = lock.withLock { samples }
        // Diagnostic: log how loud the capture actually was. When a recording
        // transcribes to "" we need to tell apart "mic captured silence" (peak
        // near 0 — a capture/device bug) from "good audio, the engine dropped it".
        var peak: Float = 0
        for s in captured { let a = abs(s); if a > peak { peak = a } }
        lastPeak = peak
        Log.write("audio level peak=\(String(format: "%.4f", peak)) samples=\(captured.count)")
        return captured
    }

    // MARK: - Tap

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let (capturing, first): (Bool, Bool) = lock.withLock {
            guard isCapturing else { return (false, false) }
            let first = !reportedFirstBuffer
            reportedFirstBuffer = true
            return (true, first)
        }
        if first { onCaptureBegan?() }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            Log.write("resample error: \(error)")
            return
        }
        guard let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        if !capturing {
            // Lingering between captures: keep only the last half second.
            lock.withLock {
                preroll.append(contentsOf: chunk)
                if preroll.count > prerollCapacity {
                    preroll.removeFirst(preroll.count - prerollCapacity)
                }
            }
            return
        }
        lock.withLock { samples.append(contentsOf: chunk) }

        // Report this buffer's peak so the HUD waveform tracks real input. When the
        // device is silent/busy this stays ~0 and the bars visibly flatten.
        if let onLevel {
            var peak: Float = 0
            for s in chunk { let a = abs(s); if a > peak { peak = a } }
            onLevel(peak)
        }
    }
}
