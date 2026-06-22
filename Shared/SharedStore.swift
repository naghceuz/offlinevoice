import Foundation

/// Tiny shared channel between the container app and the keyboard extension,
/// backed by the App Group's UserDefaults.
///
/// The round-trip: keyboard launches the app → app records & transcribes
/// on-device → app writes the text here → user returns to the host app → the
/// keyboard reads it and inserts it. The text is never thrown away on the
/// keyboard side until it's actually consumed (`takePending`), so a hiccup in
/// the hand-off can't silently lose what you said.
enum SharedStore {
    static let appGroup = "group.com.oz.offlinevoice"

    private static let kPending = "pendingTranscript"
    private static let kStamp = "pendingStamp"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Container writes the freshly transcribed text for the keyboard to pick up.
    static func setPending(_ text: String, at time: TimeInterval) {
        guard let d = defaults, !text.isEmpty else { return }
        d.set(text, forKey: kPending)
        d.set(time, forKey: kStamp)
    }

    /// Keyboard reads and clears the pending text (consume-once).
    static func takePending() -> String? {
        guard let d = defaults,
              let text = d.string(forKey: kPending),
              !text.isEmpty
        else { return nil }
        d.removeObject(forKey: kPending)
        d.removeObject(forKey: kStamp)
        return text
    }

    static var hasPending: Bool {
        (defaults?.string(forKey: kPending)?.isEmpty == false)
    }
}
