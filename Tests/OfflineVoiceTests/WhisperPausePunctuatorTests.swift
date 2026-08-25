import XCTest
@testable import OfflineVoice

final class WhisperPausePunctuatorTests: XCTestCase {
    private func word(_ text: String, start: Float, end: Float) -> PauseWord {
        PauseWord(word: text, start: start, end: end)
    }

    func testLongGapInsertsSentenceBreakAndCapitalizes() {
        // WhisperKit tokens carry their own leading space for non-initial words.
        let words = [word("Hello", start: 0, end: 0.3), word(" world", start: 1.5, end: 1.8)]
        let out = WhisperPausePunctuator.apply(words: words, language: "en")
        XCTAssertEqual(out, "Hello. World")
    }

    func testMediumGapInsertsCommaNoCapitalize() {
        let words = [word("Hello", start: 0, end: 0.3), word(" world", start: 0.7, end: 1.0)]
        let out = WhisperPausePunctuator.apply(words: words, language: "en")
        XCTAssertEqual(out, "Hello, world")
    }

    func testShortGapDoesNothing() {
        let words = [word("Hello", start: 0, end: 0.3), word(" world", start: 0.4, end: 0.7)]
        let out = WhisperPausePunctuator.apply(words: words, language: "en")
        XCTAssertEqual(out, "Hello world")
    }

    func testAlreadyPunctuatedBoundaryIsNotDoubled() {
        // WhisperKit's own mergePunctuations already folded the comma into "Hello,".
        let words = [word("Hello,", start: 0, end: 0.3), word(" world", start: 1.2, end: 1.5)]
        let out = WhisperPausePunctuator.apply(words: words, language: "en")
        XCTAssertEqual(out, "Hello, world")
    }

    func testChineseNoSpacesNoCapitalization() {
        let words = [word("你好", start: 0, end: 0.3), word("世界", start: 1.5, end: 1.8)]
        let out = WhisperPausePunctuator.apply(words: words, language: "zh")
        XCTAssertEqual(out, "你好。世界")
    }

    func testChineseCommaGap() {
        let words = [word("你好", start: 0, end: 0.3), word("世界", start: 0.7, end: 1.0)]
        let out = WhisperPausePunctuator.apply(words: words, language: "zh")
        XCTAssertEqual(out, "你好，世界")
    }

    func testSingleWordReturnsUnchanged() {
        let words = [word("Hello", start: 0, end: 0.3)]
        let out = WhisperPausePunctuator.apply(words: words, language: "en")
        XCTAssertEqual(out, "Hello")
    }

    func testEmptyReturnsEmpty() {
        XCTAssertEqual(WhisperPausePunctuator.apply(words: [], language: "en"), "")
    }

    func testNilLanguageDefaultsToLatinRules() {
        let words = [word("Hello", start: 0, end: 0.3), word(" world", start: 1.5, end: 1.8)]
        let out = WhisperPausePunctuator.apply(words: words, language: nil)
        XCTAssertEqual(out, "Hello. World")
    }

    func testNoTrailingPunctuationForcedAtEnd() {
        let words = [word("Hello", start: 0, end: 0.3), word(" world", start: 1.2, end: 1.5)]
        let out = WhisperPausePunctuator.apply(words: words, language: "en")
        XCTAssertFalse(out.hasSuffix("."))
    }
}
