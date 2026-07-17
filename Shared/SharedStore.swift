import UIKit

/// Hand-off channel between the container app and the keyboard extension.
///
/// We deliberately avoid an App Group here: that capability needs Apple Developer
/// portal registration (and a paid membership), which blocks the build on
/// personal/unconfigured accounts. A private *named* pasteboard is shared between
/// an app and its own extension, needs no entitlement, and — unlike the general
/// clipboard — doesn't clobber whatever the user had copied.
///
/// The round-trip: keyboard launches the app → app records & transcribes
/// on-device → app writes the text here → user returns to the host app → the
/// keyboard reads it (consume-once) and inserts it. The text also stays visible
/// in the app, so a hand-off hiccup can never silently lose what you said.
enum SharedStore {
    private static let name = UIPasteboard.Name("com.oz.offlinevoice.handoff")

    private static var board: UIPasteboard? {
        UIPasteboard(name: name, create: true)
    }

    /// Container writes the freshly transcribed text for the keyboard to pick up.
    static func setPending(_ text: String) {
        guard !text.isEmpty else { return }
        board?.string = text
    }

    /// Keyboard reads and clears the pending text (consume-once).
    static func takePending() -> String? {
        guard let b = board, let text = b.string, !text.isEmpty else { return nil }
        b.string = ""
        return text
    }

    static var hasPending: Bool {
        (board?.string?.isEmpty == false)
    }
}
