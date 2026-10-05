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
}
