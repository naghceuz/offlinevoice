import AVFoundation
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

enum HeadlessAudioDecoder {
    static func decode(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
            let input = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        else {
            throw error("Could not prepare audio conversion for \(url.lastPathComponent).")
        }

        try file.read(into: input)
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw error("Could not allocate converted audio for \(url.lastPathComponent).")
        }

        var suppliedInput = false
        var conversionError: NSError?
        let conversionStatus = converter.convert(to: output, error: &conversionError) { _, status in
            if suppliedInput {
                status.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            status.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }
        guard conversionStatus != .error else {
            throw error("Audio conversion failed for \(url.lastPathComponent).")
        }
        guard let channel = output.floatChannelData?[0] else {
            throw error("Converted audio contains no samples.")
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "OfflineVoice.HeadlessAudioDecoder",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

struct HeadlessTranscriptionResult: Codable, Equatable {
    let text: String
    let durationMilliseconds: Int
}

enum HeadlessTranscriptionRunner {
    static func run(
        _ command: HeadlessTranscriptionCommand,
        engine: any ASREngine
    ) async throws -> HeadlessTranscriptionResult {
        let samples = try HeadlessAudioDecoder.decode(command.audioURL)
        let start = CFAbsoluteTimeGetCurrent()
        try await engine.prepare()
        let text = try await engine.transcribe(samples)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        return HeadlessTranscriptionResult(
            text: text,
            durationMilliseconds: max(0, Int(elapsed * 1_000))
        )
    }

    static func jsonLine(for result: HeadlessTranscriptionResult) throws -> String {
        let data = try JSONEncoder().encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "OfflineVoice.HeadlessTranscriptionRunner",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode transcription result."]
            )
        }
        return json + "\n"
    }
}
