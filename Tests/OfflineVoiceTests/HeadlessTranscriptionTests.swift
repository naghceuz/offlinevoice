import AVFoundation
import XCTest
@testable import OfflineVoice

final class HeadlessTranscriptionTests: XCTestCase {
    func testTranscribeFileFlagParsesAudioPath() throws {
        let command = try XCTUnwrap(HeadlessTranscriptionCommand.parse(arguments: [
            "OfflineVoice",
            "--transcribe-file",
            "/tmp/mixed speech.wav",
        ]))

        XCTAssertEqual(command.audioURL.path, "/tmp/mixed speech.wav")
    }

    func testAudioDecoderResamplesStereoWavToSixteenKilohertzMono() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("headless-audio-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 8_000,
            channels: 2,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 800))
        buffer.frameLength = 800
        for channelIndex in 0..<2 {
            let channel = try XCTUnwrap(buffer.floatChannelData?[channelIndex])
            for frame in 0..<800 {
                channel[frame] = channelIndex == 0 ? 0.25 : -0.10
            }
        }
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }

        let samples = try HeadlessAudioDecoder.decode(url)

        XCTAssertEqual(samples.count, 1_600, accuracy: 2)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.01)
    }
}
