import AppKit
import Darwin
import Dispatch
import Foundation

// AppKit owns the global hotkey and menu bar pieces; SwiftUI owns the product UI.
@main
enum Main {
    static func main() {
        if let command = HeadlessTranscriptionCommand.parse(arguments: CommandLine.arguments) {
            runHeadless(command)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private static func runHeadless(_ command: HeadlessTranscriptionCommand) -> Never {
        Task.detached {
            do {
                let result = try await HeadlessTranscriptionRunner.run(
                    command,
                    engine: SenseVoiceEngine()
                )
                let line = try HeadlessTranscriptionRunner.jsonLine(for: result)
                FileHandle.standardOutput.write(Data(line.utf8))
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                let message = "OfflineVoice transcription failed: \(error.localizedDescription)\n"
                FileHandle.standardError.write(Data(message.utf8))
                Darwin.exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    }
}
