import AVFoundation
import XCTest
@testable import OfflineVoice

/// Runs the real bundled Silero VAD. The test host is the app bundle, so the
/// model is found the same way the app finds it.
final class SpeechGateTests: XCTestCase {
    private func benchmarkClip(_ name: String) throws -> [Float] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "benchmark")
                ?? Bundle.main.url(forResource: name, withExtension: "wav")
        )
        let file = try AVAudioFile(forReading: url)
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let converter = try XCTUnwrap(AVAudioConverter(from: file.processingFormat, to: target))
        let inBuf = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: inBuf)
        let outBuf = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(inBuf.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1_024))
        var fed = false
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        XCTAssertNil(error)
        let channel = try XCTUnwrap(outBuf.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(outBuf.frameLength)))
    }

    func testSpeechClipIsDetected() async throws {
        let gate = SpeechGate()
        let speech = try benchmarkClip("zh_original")
        let detected = try await gate.containsSpeech(speech)
        XCTAssertTrue(detected)
    }

    func testSilenceIsRejected() async throws {
        let gate = SpeechGate()
        let silence = [Float](repeating: 0, count: 16_000 * 2)
        let detected = try await gate.containsSpeech(silence)
        XCTAssertFalse(detected)
    }

    func testRoomNoiseIsRejected() async throws {
        // Deterministic noise at the amplitude the Studio Display mic reported
        // for an empty room (peak ≈ 0.015) — above the old 0.01 silence floor.
        var seed: UInt32 = 12_345
        var noise = [Float](repeating: 0, count: 16_000 * 2)
        for i in noise.indices {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            noise[i] = (Float(seed) / Float(UInt32.max) - 0.5) * 0.03
        }
        let gate = SpeechGate()
        let detected = try await gate.containsSpeech(noise)
        XCTAssertFalse(detected)
    }

    func testPinnedModelMatchesFetchScript() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/fetch-models.sh"))
        let f = SpeechGate.expectedFile
        XCTAssertTrue(script.contains("\(f.name)|\(f.size)|\(f.sha256)"))
    }
}
