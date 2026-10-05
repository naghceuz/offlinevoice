import Foundation

struct HeadlessTranscriptionCommand: Equatable {
    let audioURL: URL

    static func parse(arguments: [String]) -> HeadlessTranscriptionCommand? {
        guard let flagIndex = arguments.firstIndex(of: "--transcribe-file") else {
            return nil
        }
        let pathIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(pathIndex) else {
            return nil
        }
        return HeadlessTranscriptionCommand(
            audioURL: URL(fileURLWithPath: arguments[pathIndex])
        )
    }
}
