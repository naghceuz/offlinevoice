import AVFoundation
#if os(macOS)
import AudioToolbox
#endif

/// Captures microphone audio and resamples it to 16 kHz mono Float — the
/// format Whisper-family models expect.
final class AudioRecorder {
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

    /// Per-buffer input level (0...1 peak) reported while recording so the UI can
    /// reflect *real* mic activity. Fires on the audio thread — hop to main before
    /// touching UI.
    var onLevel: ((Float) -> Void)?

    /// Peak amplitude of the most recent completed capture (set by `stop()`).
    /// Used to tell a real recording from a near-silent one (wrong/busy device).
    private(set) var lastPeak: Float = 0

    /// Starts capture. `preferredDeviceUID` (macOS only) pins the engine to a
    /// specific input device; nil follows the system default input.
    func start(preferredDeviceUID: String? = nil) throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }

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

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops capture and returns the resampled mono samples.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Release the session on iOS so other apps regain audio; harmless no-op
        // elsewhere. Failure here must not lose the capture, so it's best-effort.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
        let captured = lock.withLock { samples }
        // Diagnostic: log how loud the capture actually was. When a recording
        // transcribes to "" we need to tell apart "mic captured silence" (peak
        // near 0 — a capture/device bug) from "good audio, Whisper dropped it".
        var peak: Float = 0
        for s in captured { let a = abs(s); if a > peak { peak = a } }
        lastPeak = peak
        Log.write("audio level peak=\(String(format: "%.4f", peak)) samples=\(captured.count)")
        return captured
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
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
