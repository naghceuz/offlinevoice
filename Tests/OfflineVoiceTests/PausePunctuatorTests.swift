import XCTest
@testable import OfflineVoice

final class PausePunctuatorTests: XCTestCase {
    /// Builds `PauseSegment`s by locating each `words` entry, in order, inside
    /// `text` (mirroring how `SFTranscriptionSegment.substringRange` is always
    /// expressed in `formattedString` coordinates), then attaches fabricated
    /// timing so callers can dial in exact inter-segment gaps.
    private func segments(in text: String, words: [String], starts: [TimeInterval], durations: [TimeInterval]) -> [PauseSegment] {
        let ns = text as NSString
        var searchStart = 0
        var result: [PauseSegment] = []
        for (i, word) in words.enumerated() {
            let range = ns.range(of: word, range: NSRange(location: searchStart, length: ns.length - searchStart))
            XCTAssertNotEqual(range.location, NSNotFound, "fixture word '\(word)' not found in '\(text)'")
            searchStart = range.location + range.length
            result.append(PauseSegment(range: range, timestamp: starts[i], duration: durations[i]))
        }
        return result
    }

    private let en = Locale(identifier: "en_US")
    private let zh = Locale(identifier: "zh_CN")

    func testLongGapInsertsSentenceBreakAndCapitalizes() {
        let text = "hello world"
        let segs = segments(in: text, words: ["hello", "world"], starts: [0, 1.5], durations: [0.3, 0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertEqual(out, "hello. World")
    }

    func testMediumGapInsertsCommaNoCapitalize() {
        let text = "hello world"
        let segs = segments(in: text, words: ["hello", "world"], starts: [0, 0.7], durations: [0.3, 0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertEqual(out, "hello, world")
    }

    func testShortGapDoesNothing() {
        let text = "hello world"
        let segs = segments(in: text, words: ["hello", "world"], starts: [0, 0.4], durations: [0.3, 0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertEqual(out, text)
    }

    func testAlreadyPunctuatedBoundaryIsNotDoubled() {
        let text = "hello, world"
        let segs = segments(in: text, words: ["hello", "world"], starts: [0, 1.2], durations: [0.3, 0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertEqual(out, text, "must not insert a second mark next to one addsPunctuation already placed")
    }

    func testOutOfBoundsRangeIsSkippedSafely() {
        let text = "hello world"
        var segs = segments(in: text, words: ["hello", "world"], starts: [0, 1.2], durations: [0.3, 0.3])
        // Simulate an OS/ITN anomaly: an out-of-bounds substringRange.
        segs[0] = PauseSegment(range: NSRange(location: 500, length: 5), timestamp: 0, duration: 0.3)
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertEqual(out, text, "an unresolvable range must be skipped, never crash or corrupt text")
    }

    func testNonMonotonicRangeIsSkippedSafely() {
        let text = "hello world foo"
        var segs = segments(in: text, words: ["hello", "world", "foo"], starts: [0, 1.5, 2.7], durations: [0.3, 0.3, 0.3])
        // Force segment 1's range to overlap segment 0's — an anomaly the
        // monotonicity guard must reject rather than act on. Segment 1 is the
        // anchor for the 1->2 boundary, so corrupting it must only suppress
        // that boundary's insertion, leaving the unrelated 0->1 boundary
        // (anchored on the untouched segment 0) to punctuate normally.
        segs[1] = PauseSegment(range: NSRange(location: 0, length: 5), timestamp: 1.5, duration: 0.3)
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertEqual(out, "hello. World foo")
    }

    func testChineseLocaleUsesFullWidthPunctuationNoCapitalization() {
        let text = "你好世界"
        let segs = segments(in: text, words: ["你好", "世界"], starts: [0, 1.5], durations: [0.3, 0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: zh)
        XCTAssertEqual(out, "你好。世界")
    }

    func testChineseLocaleCommaGap() {
        let text = "你好世界"
        let segs = segments(in: text, words: ["你好", "世界"], starts: [0, 0.7], durations: [0.3, 0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: zh)
        XCTAssertEqual(out, "你好，世界")
    }

    func testSingleSegmentReturnsUnchanged() {
        let text = "hello"
        let segs = segments(in: text, words: ["hello"], starts: [0], durations: [0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertEqual(out, text)
    }

    func testEmptyStringReturnsUnchanged() {
        let out = PausePunctuator.apply(formattedString: "", segments: [], locale: en)
        XCTAssertEqual(out, "")
    }

    func testNoTrailingPunctuationForcedAtEnd() {
        // The algorithm only inserts *between* segments; it must never append
        // anything after the final one, even though there's no following gap
        // to measure.
        let text = "hello world"
        let segs = segments(in: text, words: ["hello", "world"], starts: [0, 1.2], durations: [0.3, 0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertFalse(out.hasSuffix("."))
    }

    func testNoDoubleSpaceAfterInsertedMark() {
        let text = "hello world"
        let segs = segments(in: text, words: ["hello", "world"], starts: [0, 1.2], durations: [0.3, 0.3])
        let out = PausePunctuator.apply(formattedString: text, segments: segs, locale: en)
        XCTAssertFalse(out.contains("  "), "must not produce a double space when Apple's own spacing already separates words")
    }
}
