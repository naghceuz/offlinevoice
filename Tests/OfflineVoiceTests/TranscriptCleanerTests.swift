import XCTest
@testable import OfflineVoice

final class TranscriptCleanerTests: XCTestCase {
    func testSpacesBetweenChineseAndLatinRuns() {
        XCTAssertEqual(TranscriptCleaner.apply("中文和english混在一起说。"), "中文和 english 混在一起说。")
        XCTAssertEqual(TranscriptCleaner.apply("我现在说中文mix英文。"), "我现在说中文 mix 英文。")
    }

    func testExistingSpacesAreNotDoubled() {
        XCTAssertEqual(TranscriptCleaner.apply("中文和 english 混在一起"), "中文和 english 混在一起")
    }

    func testDigitsCountAsLatin() {
        XCTAssertEqual(TranscriptCleaner.apply("今天下午3点开会"), "今天下午 3 点开会")
    }

    func testNoSpaceBeforeCJKPunctuation() {
        XCTAssertEqual(TranscriptCleaner.apply("调到max。"), "调到 max。")
    }

    func testRepeatedTerminalMarksCollapse() {
        XCTAssertEqual(TranscriptCleaner.apply("中文和english。。"), "中文和 english。")
        XCTAssertEqual(TranscriptCleaner.apply("Really?? Yes.."), "Really? Yes.")
    }

    func testPureEnglishAndPureChineseUntouched() {
        XCTAssertEqual(TranscriptCleaner.apply("Let me mix Chinese and English."), "Let me mix Chinese and English.")
        XCTAssertEqual(TranscriptCleaner.apply("今天我们要去开会。"), "今天我们要去开会。")
    }

    func testJapaneseAndKoreanAreCJK() {
        XCTAssertEqual(TranscriptCleaner.apply("これはtestです"), "これは test です")
        XCTAssertEqual(TranscriptCleaner.apply("이것은test입니다"), "이것은 test 입니다")
    }
}
