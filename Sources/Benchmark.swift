import AVFoundation
import CoreML
import Foundation
import WhisperKit

/// Developer-only engine benchmark. Loads WhisperKit under a matrix of
/// (model variant × audio-encoder compute unit) and measures cold-load time,
/// first-inference latency, repeated-inference latency, peak memory, and
/// transcription quality (WER for English, CER for Chinese) against the bundled
/// corpus in `Resources/benchmark/`.
///
/// Results append to `/tmp/offlinevoice-benchmark.md`. Triggered from the
/// DEBUG-only button on the Speed & Accuracy page or the `--benchmark` CLI flag.
/// This never touches the live engine path — it builds throwaway WhisperKit
/// instances so we can read `currentTimings` and try compute configs in isolation.
enum Benchmark {
    static let outputPath = "/tmp/offlinevoice-benchmark.md"

    /// Model variants to compare. Missing local folders are logged and skipped.
    private static let models = [
        "large-v3-v20240930_turbo",       // current default — full 1.2GB encoder
        "large-v3-v20240930_turbo_632MB", // quantized
        "distil-whisper_distil-large-v3_turbo_600MB", // distilled
    ]

    /// Audio-encoder compute units to A/B (other components keep WhisperKit
    /// defaults). nil-encoder means WhisperKit's own default (ANE on macOS 14+).
    private static let computeVariants: [(label: String, encoder: MLComputeUnits)] = [
        ("ANE", .cpuAndNeuralEngine),
        ("GPU", .cpuAndGPU),
        ("ALL", .all),
    ]

    private static let repeatRuns = 5

    // MARK: - Entry point

    static func run() {
        Task.detached(priority: .utility) {
            await runMatrix()
        }
    }

    private static func runMatrix() async {
        Log.write("benchmark: starting")
        let corpus: [Sample]
        do {
            corpus = try loadCorpus()
        } catch {
            Log.write("benchmark: failed to load corpus: \(error)")
            return
        }
        Log.write("benchmark: corpus loaded (\(corpus.count) samples)")

        var rows: [Row] = []
        for model in models {
            guard modelFolderExists(model) else {
                Log.write("benchmark: model folder missing, skipping \(model)")
                continue
            }
            for variant in computeVariants {
                if let row = await measure(model: model, variant: variant, corpus: corpus) {
                    rows.append(row)
                    Log.write("benchmark: \(model) [\(variant.label)] load=\(Int(row.loadMs))ms first=\(Int(row.firstMs))ms mean=\(Int(row.meanMs))ms peak=\(Int(row.peakMB))MB")
                }
            }
        }

        writeReport(rows: rows, corpus: corpus)
        Log.write("benchmark: done — wrote \(outputPath) (\(rows.count) rows)")
    }

    // MARK: - One configuration

    private static func measure(model: String, variant: (label: String, encoder: MLComputeUnits), corpus: [Sample]) async -> Row? {
        let options = ModelComputeOptions(audioEncoderCompute: variant.encoder)
        let config = makeConfig(model: model, computeOptions: options)
        Log.write("benchmark: loading \(model) [\(variant.label)]…")

        let memBefore = residentMB()
        let loadStart = CFAbsoluteTimeGetCurrent()
        let kit: WhisperKit
        do {
            kit = try await WhisperKit(config)
        } catch {
            Log.write("benchmark: load failed \(model) [\(variant.label)]: \(error)")
            return nil
        }
        let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        var peakMB = max(residentMB(), memBefore)

        let t = kit.currentTimings

        // First-inference latency (warms ANE specialization for this instance).
        var firstMs = 0.0
        var inferTimes: [Double] = []
        var outputs: [String] = []

        for (i, sample) in corpus.enumerated() {
            let start = CFAbsoluteTimeGetCurrent()
            let text = (try? await transcribe(kit, sample)) ?? ""
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if i == 0 { firstMs = ms }
            inferTimes.append(ms)
            outputs.append(text)
            peakMB = max(peakMB, residentMB())
        }

        // Repeat the corpus to gauge steady-state latency (skip the cold first pass).
        var repeatTimes: [Double] = []
        for _ in 0..<repeatRuns {
            for sample in corpus {
                let start = CFAbsoluteTimeGetCurrent()
                _ = try? await transcribe(kit, sample)
                repeatTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            peakMB = max(peakMB, residentMB())
        }
        let meanMs = repeatTimes.isEmpty ? (inferTimes.reduce(0, +) / Double(max(inferTimes.count, 1))) : repeatTimes.reduce(0, +) / Double(repeatTimes.count)

        // Quality vs references.
        var werSum = 0.0, werN = 0, cerSum = 0.0, cerN = 0
        var qualityNotes: [String] = []
        for (sample, hyp) in zip(corpus, outputs) {
            switch sample.lang {
            case "en":
                let w = wer(reference: sample.text, hypothesis: hyp)
                werSum += w; werN += 1
                qualityNotes.append("\(sample.file): WER \(pct(w)) → \(trim(hyp))")
            default: // zh / mixed → char error rate
                let c = cer(reference: sample.text, hypothesis: hyp)
                cerSum += c; cerN += 1
                qualityNotes.append("\(sample.file): CER \(pct(c)) → \(trim(hyp))")
            }
        }

        return Row(
            model: model,
            compute: variant.label,
            loadMs: loadMs,
            encoderLoadMs: t.encoderLoadTime * 1000,
            encoderSpecMs: t.encoderSpecializationTime * 1000,
            firstMs: firstMs,
            meanMs: meanMs,
            peakMB: peakMB,
            wer: werN > 0 ? werSum / Double(werN) : nil,
            cer: cerN > 0 ? cerSum / Double(cerN) : nil,
            quality: qualityNotes
        )
    }

    private static func transcribe(_ kit: WhisperKit, _ sample: Sample) async throws -> String {
        // Never tell the model the clip's language: the live engine runs with
        // auto-detection, and a benchmark that pre-announces zh/en would hide
        // exactly the mixed-language failures we care about. `sample.lang` is
        // only used to pick the WER/CER metric.
        let options = DecodingOptions(task: .transcribe, language: nil, detectLanguage: true)
        let results = try await kit.transcribe(audioArray: sample.samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Corpus

    private struct Sample {
        let file: String
        let lang: String
        let text: String
        let samples: [Float]
    }

    private static func loadCorpus() throws -> [Sample] {
        guard let jsonURL = resourceURL("references", "json") else {
            throw err("references.json not found in bundle")
        }
        let data = try Data(contentsOf: jsonURL)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["samples"] as? [[String: Any]]
        else { throw err("references.json malformed") }

        return try items.compactMap { item in
            guard
                let file = item["file"] as? String,
                let lang = item["lang"] as? String,
                let text = item["text"] as? String
            else { return nil }
            let name = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            guard let wav = resourceURL(name, ext) else {
                Log.write("benchmark: sample wav missing \(file)")
                return nil
            }
            return Sample(file: file, lang: lang, text: text, samples: try decodeWav(wav))
        }
    }

    /// Looks the resource up both flattened at the bundle root and under a
    /// `benchmark` subdirectory, since XcodeGen may add the folder either way.
    private static func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "benchmark")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    /// Decodes a WAV file to 16 kHz mono Float — matching the live capture format.
    private static func decodeWav(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: target),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw err("decodeWav: buffer/converter setup failed for \(url.lastPathComponent)") }

        try file.read(into: inBuf)
        let ratio = target.sampleRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 1_024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else {
            throw err("decodeWav: output buffer alloc failed")
        }

        var fed = false
        var convError: NSError?
        converter.convert(to: outBuf, error: &convError) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return inBuf
        }
        if let convError { throw convError }
        guard let channel = outBuf.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outBuf.frameLength)))
    }

    // MARK: - Local-only model config (mirrors WhisperKitEngine)

    private static func modelBase() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models")
    }

    private static func modelFolderExists(_ model: String) -> Bool {
        FileManager.default.fileExists(atPath: modelFolder(model).path)
    }

    private static func modelFolder(_ model: String) -> URL {
        modelBase().appendingPathComponent("argmaxinc/whisperkit-coreml/openai_whisper-\(model)")
    }

    private static func makeConfig(model: String, computeOptions: ModelComputeOptions) -> WhisperKitConfig {
        let tokenizerFolder = modelBase().appendingPathComponent("openai/whisper-large-v3")
        let fm = FileManager.default
        return WhisperKitConfig(
            model: model,
            modelFolder: modelFolder(model).path,
            tokenizerFolder: fm.fileExists(atPath: tokenizerFolder.path) ? tokenizerFolder : nil,
            computeOptions: computeOptions,
            download: false
        )
    }

    // MARK: - Metrics

    private struct Row {
        let model: String
        let compute: String
        let loadMs: Double
        let encoderLoadMs: Double
        let encoderSpecMs: Double
        let firstMs: Double
        let meanMs: Double
        let peakMB: Double
        let wer: Double?
        let cer: Double?
        let quality: [String]
    }

    /// Resident memory in MB for the whole process (best-effort).
    private static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    /// Word error rate after lowercasing and stripping punctuation.
    private static func wer(reference: String, hypothesis: String) -> Double {
        let ref = tokenizeWords(reference)
        let hyp = tokenizeWords(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    /// Character error rate — strips whitespace and punctuation, compares chars.
    private static func cer(reference: String, hypothesis: String) -> Double {
        let ref = Array(normalizeChars(reference))
        let hyp = Array(normalizeChars(hypothesis))
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    private static func tokenizeWords(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func normalizeChars(_ s: String) -> [Character] {
        s.lowercased().filter { ch in
            !ch.isWhitespace && !ch.isPunctuation && !ch.isSymbol
        }
    }

    private static func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    // MARK: - Report

    private static func writeReport(rows: [Row], corpus: [Sample]) {
        var md = "\n# OfflineVoice engine benchmark — \(timestamp())\n\n"
        md += "Corpus: \(corpus.count) clips (\(corpus.map(\.file).joined(separator: ", "))). "
        md += "TTS-synthesized, so absolute WER/CER reads optimistic — compare rows relatively.\n\n"
        md += "| Model | Encoder | Load (ms) | EncLoad | EncSpec | First infer | Mean infer | Peak MB | WER | CER |\n"
        md += "|---|---|--:|--:|--:|--:|--:|--:|--:|--:|\n"
        for r in rows {
            md += "| \(r.model) | \(r.compute) | \(Int(r.loadMs)) | \(Int(r.encoderLoadMs)) | \(Int(r.encoderSpecMs)) | \(Int(r.firstMs)) | \(Int(r.meanMs)) | \(Int(r.peakMB)) | \(r.wer.map(pct) ?? "—") | \(r.cer.map(pct) ?? "—") |\n"
        }
        md += "\n## Sample outputs\n\n"
        for r in rows {
            md += "### \(r.model) [\(r.compute)]\n"
            for q in r.quality { md += "- \(q)\n" }
            md += "\n"
        }

        let line = md.data(using: .utf8) ?? Data()
        let url = URL(fileURLWithPath: outputPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    private static func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
    private static func trim(_ s: String) -> String { s.count > 60 ? String(s.prefix(60)) + "…" : s }
    private static func err(_ msg: String) -> NSError {
        NSError(domain: "OfflineVoice.Benchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
