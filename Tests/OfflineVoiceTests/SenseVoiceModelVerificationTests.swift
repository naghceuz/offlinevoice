import XCTest
@testable import OfflineVoice

/// The bundled-model integrity gate in `SenseVoiceEngine`. These never reach
/// sherpa-onnx: a corrupt model crashes the process inside onnxruntime, so the
/// whole point is that every bad input is rejected with a Swift error first.
final class SenseVoiceModelVerificationTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sensevoice-verify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, bytes: Int) throws {
        try Data(repeating: 0x41, count: bytes).write(to: dir.appendingPathComponent(name))
    }

    private func prepareError(file: StaticString = #filePath, line: UInt = #line) async -> String {
        let engine = SenseVoiceEngine(modelDirectory: dir)
        do {
            try await engine.prepare()
            XCTFail("prepare() should have thrown", file: file, line: line)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    func testMissingModelFileIsReportedByName() async throws {
        let message = await prepareError()
        XCTAssertTrue(message.contains("missing"), message)
        XCTAssertTrue(message.contains("model.int8.onnx"), message)
    }

    func testWrongSizeIsRejectedBeforeHashing() async throws {
        try write("model.int8.onnx", bytes: 1_024)
        try write("tokens.txt", bytes: 1_024)
        let message = await prepareError()
        XCTAssertTrue(message.contains("wrong size"), message)
    }

    func testRightSizeWrongContentFailsIntegrityCheck() async throws {
        // Exactly the pinned size of tokens.txt, but not its contents. The model
        // is checked first, so give it the right size too to reach tokens.
        let files = SenseVoiceEngine.expectedFiles
        for file in files { try write(file.name, bytes: file.size) }
        let message = await prepareError()
        XCTAssertTrue(message.contains("integrity"), message)
    }

    func testPinnedTableMatchesFetchScript() throws {
        // Guards against the Swift table and scripts/fetch-models.sh drifting apart.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/fetch-models.sh"))
        for file in SenseVoiceEngine.expectedFiles {
            XCTAssertTrue(script.contains("\(file.name)|\(file.size)|\(file.sha256)"),
                          "fetch-models.sh does not pin \(file.name) to \(file.size)/\(file.sha256)")
        }
    }
}
