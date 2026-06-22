import SwiftUI

/// iOS host app entry point.
///
/// Two ways in:
/// 1. Opened directly → the standalone dictation surface (`DictationView`).
/// 2. Opened via `offlinevoice://dictate` from the keyboard → a full-screen
///    round-trip recorder (`RoundTripView`) that hands text back to the keyboard.
@main
struct OfflineVoiceApp: App {
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            DictationView()
                .preferredColorScheme(.dark)
                .fullScreenCover(isPresented: $router.roundTripActive) {
                    RoundTripView()
                }
                .onOpenURL { url in
                    if url.scheme == "offlinevoice", url.host == "dictate" {
                        router.roundTripActive = true
                    }
                }
        }
    }
}

@MainActor
final class Router: ObservableObject {
    @Published var roundTripActive = false
}
