import Foundation

/// Light, language-agnostic cleanup applied to engine output before pasting.
/// Pure function so it is unit-testable.
///
/// SenseVoice's inverse text normalization adds punctuation but strips the
/// spaces between Chinese and Latin runs ("中文和english混在一起"); mixed-script
/// text is conventionally set with a space on each side of the Latin word
/// ("中文和 english 混在一起"), which is also what every reference transcript in
/// this repo uses. It can also emit the same terminal mark twice at a segment
/// boundary ("。。"); collapse those.
enum TranscriptCleaner {
    static func apply(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count + 8)
        var previous: Character?
        for ch in text {
            if let prev = previous {
                // Collapse immediately repeated terminal punctuation.
                if isTerminal(ch), ch == prev { continue }
                // Space between a CJK ideograph and a Latin letter/digit, both ways.
                if (isCJK(prev) && isLatinOrDigit(ch)) || (isLatinOrDigit(prev) && isCJK(ch)) {
                    out.append(" ")
                }
            }
            out.append(ch)
            previous = ch
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F, // Han
             0x3040...0x30FF, // Hiragana / Katakana
             0xAC00...0xD7AF: // Hangul
            return true
        default:
            return false
        }
    }

    private static func isLatinOrDigit(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber)
    }

    private static func isTerminal(_ ch: Character) -> Bool {
        PausePunctuator.terminalMarks.contains(ch) && ch != "\n"
    }
}
