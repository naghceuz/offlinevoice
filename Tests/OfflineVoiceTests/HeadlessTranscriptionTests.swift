import AVFoundation
import XCTest
@testable import OfflineVoice

final class HeadlessTranscriptionTests: XCTestCase {
    private actor CapturingEngine: ASREngine {
        private(set) var receivedSampleCount = 0

        func transcribe(_ samples: [Float]) async throws -> String {
            receivedSampleCount = samples.count
            return "我想试着用一用"
        }
    }

    func testTranscribeFileFlagParsesAudioPath() throws {
        let command = try XCTUnwrap(HeadlessTranscriptionCommand.parse(arguments: [
            "OfflineVoice",
            "--transcribe-file",
            "/tmp/mixed speech.wav",
        ]))

        XCTAssertEqual(command.audioURL.path, "/tmp/mixed speech.wav")
    }

    func testTranscribeFileFlagWithoutPathThrowsUsageError() {
        XCTAssertThrowsError(
            try HeadlessTranscriptionCommand.parse(arguments: ["OfflineVoice", "--transcribe-file"])
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("requires a WAV file path"))
        }
    }

    func testAudioDecoderResamplesStereoWavToSixteenKilohertzMono() throws {
        let url = try makeWav(sampleRate: 8_000, channels: 2, frames: 8_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try HeadlessAudioDecoder.decode(url)

        XCTAssertEqual(samples.count, 16_000, accuracy: 2)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.01)
    }

    func testRunnerTranscribesDecodedAudioAndReturnsResult() async throws {
        let url = try makeWav(sampleRate: 16_000, channels: 1, frames: 1_600)
        defer { try? FileManager.default.removeItem(at: url) }
        let command = HeadlessTranscriptionCommand(audioURL: url)
        let engine = CapturingEngine()

        let result = try await HeadlessTranscriptionRunner.run(command, engine: engine)
        let receivedSampleCount = await engine.receivedSampleCount

        XCTAssertEqual(result.text, "我想试着用一用")
        XCTAssertGreaterThan(receivedSampleCount, 1_500)
        XCTAssertGreaterThanOrEqual(result.durationMilliseconds, 0)
    }

    func testResultEncodesAsOneJSONLine() throws {
        let result = HeadlessTranscriptionResult(
            text: "我们用 OfflineVoice test",
            durationMilliseconds: 87
        )

        let line = try HeadlessTranscriptionRunner.jsonLine(for: result)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )

        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertEqual(object["text"] as? String, "我们用 OfflineVoice test")
        XCTAssertEqual(object["durationMilliseconds"] as? Int, 87)
    }

    private func makeWav(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frames: AVAudioFrameCount
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-audio-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channelIndex in 0..<Int(channels) {
            let channel = try XCTUnwrap(buffer.floatChannelData?[channelIndex])
            for frame in 0..<Int(frames) {
                channel[frame] = channelIndex == 0 ? 0.25 : -0.10
            }
        }
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        return url
    }
}
