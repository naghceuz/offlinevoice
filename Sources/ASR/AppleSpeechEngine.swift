import AVFoundation
import Foundation
import Speech

/// Minimal, mockable view of an `SFTranscriptionSegment`'s pause-timing data.
/// `SFTranscriptionSegment` has no public initializer, so pure logic that
/// operates on this data takes a plain struct instead — makes it testable
/// without a live SFSpeechRecognizer session.
struct PauseSegment: Equatable {
    /// Same as `SFTranscriptionSegment.substringRange`: already expressed in
    /// `SFTranscription.formattedString`'s UTF-16 coordinates.
    let range: NSRange
    let timestamp: TimeInterval
    let duration: TimeInterval
}

/// Turns natural pause timing between recognized words into commas/periods.
/// Built entirely from timestamps SFSpeechRecognizer already computes as part
/// of a normal transcription — no model, no extra pass, sub-millisecond cost.
/// Kept as a pure function (String in, String out) so it's unit-testable in
/// isolation from the engine/actor.
enum PausePunctuator {
    /// Below this gap: ordinary word-to-word spacing — do nothing. Typical
    /// intra-clause pauses (breathing, word-finding) in spontaneous speech run
    /// roughly 250-350ms; punctuating below this would mark normal cadence.
    static let commaGap: TimeInterval = 0.30

    /// Above this gap: treat it as a sentence boundary rather than a comma.
    /// Between commaGap and sentenceGap = comma-level break. An initial 0.70
    /// classified *every* pause in extemporaneous (unscripted) speech as
    /// sentence-level; widened to 1.1 and validated against real dictation
    /// (gaps of ~0.3-0.4s at clause breaks correctly landed as commas, ~1.4s+
    /// between distinct thoughts correctly landed as sentence breaks).
    static let sentenceGap: TimeInterval = 1.1

    /// How far past an inserted mark to look for a letter to capitalize
    /// (Latin scripts only). Bounded small: this only needs to skip a stray
    /// space/quote, and a small bound keeps the scan from reaching into a
    /// different, already-mutated insertion point.
    private static let capitalizeLookahead = 4

    /// Internal (not private) so `WhisperPausePunctuator` can share the same
    /// "already punctuated, don't double up" check.
    static let terminalMarks: Set<Character> = [
        ",", "，", ".", "。", "!", "！", "?", "？", ";", "；", ":", "：", "、", "…", "\n",
    ]

    static func apply(formattedString: String, segments: [PauseSegment], locale: Locale) -> String {
        guard segments.count > 1, !formattedString.isEmpty else { return formattedString }

        let isCJK = ["zh", "ja"].contains(locale.language.languageCode?.identifier ?? "")

        struct Insertion { let at: String.Index; let mark: Character; let capitalizeNext: Bool }
        var insertions: [Insertion] = []
        var lastAccepted: String.Index?

        for i in 0..<(segments.count - 1) {
            let gap = segments[i + 1].timestamp - (segments[i].timestamp + segments[i].duration)
            guard gap > commaGap else { continue }

            // Resolve this segment's end position in formattedString. Returns
            // nil for any out-of-bounds/misaligned range (ITN edge cases,
            // OS quirks) — that's our "skip, don't guess" guard.
            guard let r = Range(segments[i].range, in: formattedString) else { continue }

            // Defensive monotonicity check: refuse to insert at or before a
            // point already used. Not expected in practice (segments are
            // documented to be in transcript order) but turns any OS-level
            // range anomaly into "skip" rather than corrupted output.
            if let last = lastAccepted, r.upperBound <= last { continue }
            let at = r.upperBound
            lastAccepted = at

            // Don't double up if formattedString already has punctuation
            // right at this boundary (Apple's own addsPunctuation may have
            // already placed one here).
            if at < formattedString.endIndex, terminalMarks.contains(formattedString[at]) { continue }
            if at > formattedString.startIndex,
               terminalMarks.contains(formattedString[formattedString.index(before: at)]) { continue }

            let isSentence = gap > sentenceGap
            let mark: Character = isSentence ? (isCJK ? "。" : ".") : (isCJK ? "，" : ",")
            insertions.append(Insertion(at: at, mark: mark, capitalizeNext: !isCJK && isSentence))
        }

        guard !insertions.isEmpty else { return formattedString }

        var out = formattedString
        // Apply strictly right-to-left. Every `at` above was computed against
        // the pristine, unmutated `formattedString`; inserting from the
        // rightmost boundary first guarantees every not-yet-applied index is
        // still to the LEFT of anything already mutated, so it stays valid.
        for ins in insertions.sorted(by: { $0.at > $1.at }) {
            out.insert(ins.mark, at: ins.at)
            var cursor = out.index(after: ins.at)
            // `cursor` now points at whatever followed the word boundary in the
            // original text — for Latin scripts that's almost always the space
            // Apple already put between words. Only add one if it's missing, or
            // formattedString ends up with a double space after the mark.
            if !isCJK, cursor == out.endIndex || !out[cursor].isWhitespace {
                out.insert(" ", at: cursor)
                cursor = out.index(after: cursor)
            }
            if ins.capitalizeNext {
                var steps = 0
                while cursor < out.endIndex, !out[cursor].isLetter, steps < capitalizeLookahead {
                    cursor = out.index(after: cursor)
                    steps += 1
                }
                if cursor < out.endIndex, out[cursor].isLetter {
                    out.replaceSubrange(cursor...cursor, with: out[cursor].uppercased())
                }
            }
        }
        return out
    }
}

/// On-device transcription via Apple's own Speech framework (SFSpeechRecognizer).
///
/// Fully native: no model download, no background service, no Python. This is
/// the "Apple native" path — the lightest and most private engine. Pause
/// timing between recognized words (already computed by the OS) is used to
/// add commas/periods where `addsPunctuation` misses continuous, unpaused
/// speech — see `PausePunctuator`. On-device recognition keeps audio on this
/// Mac.
actor AppleSpeechEngine: ASREngine {
    private let locale: Locale
    private var recognizer: SFSpeechRecognizer?

    /// Max time to wait for a final result before giving up. Apple's recognizer
    /// occasionally never delivers `isFinal`; without this the Pipeline would be
    /// stuck in `.processing` forever and swallow every later hotkey press.
    private let recognitionTimeout: Duration = .seconds(15)

    /// Defaults to the system locale so English (and every other) Mac gets
    /// sensible recognition out of the box — no hardcoded Chinese.
    init(locale: Locale = .current) {
        self.locale = locale
    }

    func prepare() async throws {
        try await Self.requestAuthorization()
        guard let rec = SFSpeechRecognizer(locale: locale) else {
            throw err("No speech recognizer for locale \(locale.identifier).")
        }
        guard rec.isAvailable else {
            throw err("Apple speech recognizer is not available right now.")
        }
        // Offline-first: refuse to fall back to Apple's servers. If the on-device
        // model for this locale isn't installed, surface it instead of leaking audio.
        guard rec.supportsOnDeviceRecognition else {
            throw err("On-device speech for \(locale.identifier) isn't installed. Enable Dictation in System Settings ▸ Keyboard so macOS downloads the local model, then retry.")
        }
        Log.write("AppleSpeech ready locale=\(locale.identifier) onDevice=true")
        recognizer = rec
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let rec = try await loaded()
        let locale = self.locale
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        // Force fully-local recognition so nothing leaves the Mac, when the
        // on-device model for this locale is installed.
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        guard let buffer = Self.makeBuffer(from: samples) else {
            throw err("Could not build the audio buffer for Apple speech.")
        }
        request.append(buffer)
        request.endAudio()

        // Guards the three resume paths (final result, error, timeout) so the
        // continuation is resumed exactly once even though the recognizer
        // callback fires on an arbitrary queue.
        let lock = NSLock()
        var resumed = false
        var task: SFSpeechRecognitionTask?
        let timeout = recognitionTimeout

        return try await withCheckedThrowingContinuation { continuation in
            func finish(_ work: () -> Void) {
                lock.lock(); defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                work()
            }

            // The task is held by the recognizer until the final result; we only
            // care about the final transcription for paste-and-go dictation.
            task = rec.recognitionTask(with: request) { result, error in
                if let error {
                    finish { continuation.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal else { return }
                finish {
                    let pauseSegments = result.bestTranscription.segments.map {
                        PauseSegment(range: $0.substringRange, timestamp: $0.timestamp, duration: $0.duration)
                    }
                    let punctuated = PausePunctuator.apply(
                        formattedString: result.bestTranscription.formattedString,
                        segments: pauseSegments,
                        locale: locale
                    )
                    continuation.resume(returning: punctuated.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            // Fallback: if Apple's recognizer never delivers a final result,
            // cancel it and surface a timeout so the Pipeline returns to idle.
            Task {
                try? await Task.sleep(for: timeout)
                finish {
                    task?.cancel()
                    continuation.resume(throwing: self.err("Apple speech timed out after \(timeout). Try again."))
                }
            }
        }
    }

    private func loaded() async throws -> SFSpeechRecognizer {
        if let recognizer { return recognizer }
        try await prepare()
        guard let recognizer else { throw err("Apple speech recognizer failed to load.") }
        return recognizer
    }

    // MARK: - Helpers

    private func err(_ message: String) -> NSError {
        NSError(domain: "OfflineVoice.AppleSpeech", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func requestAuthorization() async throws {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw NSError(domain: "OfflineVoice.AppleSpeech", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Speech Recognition permission is needed for Apple-native mode (System Settings ▸ Privacy ▸ Speech Recognition)."])
        }
    }

    /// Wraps 16 kHz mono Float samples into the PCM buffer SFSpeech expects.
    private static func makeBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channel[0].update(from: base, count: samples.count) }
        }
        return buffer
    }
}
