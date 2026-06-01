#if EVAL_CAPTURE

#if !DEBUG
#error("EVAL_CAPTURE must only be defined alongside DEBUG. Check project.yml — it must never appear in any Release configuration.")
#endif

import CryptoKit
import Foundation
import ZIPFoundation

public enum EvalPreferenceKey {
    public static let evalCaptureEnabled = "notabene.eval_capture_enabled"
}

/// Owns the on-disk eval dataset (`<Documents>/EvalSamples/`).
///
/// See `docs/eval-capture.md` for the full spec. Every method here is gated by
/// `#if EVAL_CAPTURE`; the entire writer compiles out of any build that
/// doesn't define the flag.
public actor EvalSampleWriter {
    public enum WriteError: Error, CustomStringConvertible {
        case templateMismatch(file: String)
        case imageEncodeFailed
        case sampleJSONFailed(underlying: Error)
        case ioFailed(underlying: Error)

        public var description: String {
            switch self {
            case .templateMismatch(let file):
                return "eval-capture: in-memory request template for \(file) differs from on-disk file; bump the corresponding ExtractionPrompts version constant."
            case .imageEncodeFailed:
                return "eval-capture: failed to detect image format"
            case .sampleJSONFailed(let err):
                return "eval-capture: sample.json serialization failed (\(err))"
            case .ioFailed(let err):
                return "eval-capture: filesystem write failed (\(err))"
            }
        }
    }

    public struct LastWrite: Sendable {
        public let timestamp: Date
        public let succeeded: Bool
        public let message: String?

        public init(timestamp: Date, succeeded: Bool, message: String?) {
            self.timestamp = timestamp
            self.succeeded = succeeded
            self.message = message
        }
    }

    public struct DirSnapshot: Sendable {
        public let sampleCount: Int
        public let totalBytes: Int64
        public let lastWrite: LastWrite?

        public init(sampleCount: Int, totalBytes: Int64, lastWrite: LastWrite?) {
            self.sampleCount = sampleCount
            self.totalBytes = totalBytes
            self.lastWrite = lastWrite
        }
    }

    public static let shared = EvalSampleWriter()

    private let fm = FileManager.default
    private let root: URL
    private let staging: URL
    private let templates: URL
    private var lastWrite: LastWrite?
    private var didInitDirs = false

    public init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = base.appendingPathComponent("EvalSamples", isDirectory: true)
        self.staging = self.root.appendingPathComponent(".in_progress", isDirectory: true)
        self.templates = self.root.appendingPathComponent("request_templates", isDirectory: true)
    }

    // MARK: - Snapshot

    public func snapshot() -> DirSnapshot {
        try? ensureDirs()
        let urls = (try? sampleFolderURLs()) ?? []
        let totalBytes = directorySize(at: root)
        return DirSnapshot(sampleCount: urls.count, totalBytes: totalBytes, lastWrite: lastWrite)
    }

    // MARK: - Write

    /// Writes one sample (an image set + parsed/raw model response + book +
    /// provider/model metadata) to disk atomically. Hash-checks the matching
    /// request template against the in-memory version and crashes loud if they
    /// differ — that means the prompt or schema changed without a version bump.
    public func writeSample(
        trace: ExtractionTrace,
        images: [Data],
        provider: LLMProvider,
        model: String,
        book: Book,
        appVersion: String,
        appBuild: String,
        platform: String,
        deviceModel: String,
        clock: () -> Date = { Date() }
    ) throws {
        do {
            try ensureDirs()

            let pageCount = images.count
            let variant = ExtractionPrompts.variantName(forPageCount: pageCount)
            let version = ExtractionPrompts.extractionVersion(forPageCount: pageCount)
            let templateFile = "\(provider.rawValue)-\(variant)-\(version).json"
            let templateRelPath = "request_templates/\(templateFile)"

            try ensureTemplateFile(provider: provider, pageCount: pageCount, templateFile: templateFile)

            let now = clock()
            let sampleID = Self.sampleID(at: now)

            let stagingDir = staging.appendingPathComponent(sampleID, isDirectory: true)
            try? fm.removeItem(at: stagingDir)
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            // Images: write raw bytes, sniff format for extension + metadata.
            var photoNames: [String] = []
            var photoMeta: [[String: Any]] = []
            for (idx, data) in images.enumerated() {
                let format = ImageFormat.sniff(data)
                let filename = "image_\(idx + 1).\(format.fileExtension)"
                let dest = stagingDir.appendingPathComponent(filename)
                try data.write(to: dest, options: [.atomic])

                var meta: [String: Any] = [
                    "file": filename,
                    "bytes": data.count,
                    "detected_format": format.label,
                    "request_mime": trace.requestMime,
                ]
                if let (w, h) = format.pixelSize(of: data) {
                    meta["width"] = w
                    meta["height"] = h
                }
                photoNames.append(filename)
                photoMeta.append(meta)
            }

            // sample.json
            let sampleJSON: [String: Any] = [
                "schema_version": 1,
                "sample_id": sampleID,
                "captured_at": Self.iso8601(now),
                "request_template": templateRelPath,
                "photos": photoNames,
                "provider": provider.rawValue,
                "model": model,
                "app": [
                    "version": appVersion,
                    "build": appBuild,
                    "platform": platform,
                    "device_model": deviceModel,
                ],
                "book": [
                    "title": book.title,
                    "author": book.author as Any? ?? NSNull(),
                    "source": book.source.rawValue,
                ],
                "response": [
                    "parsed": Self.encodeParsed(trace.result),
                    "raw": trace.rawResponseBody,
                    "latency_ms": trace.latencyMillis,
                ],
                "photo_meta": photoMeta,
            ]
            let sampleData: Data
            do {
                sampleData = try JSONSerialization.data(
                    withJSONObject: sampleJSON,
                    options: [.prettyPrinted, .sortedKeys]
                )
            } catch {
                throw WriteError.sampleJSONFailed(underlying: error)
            }
            try sampleData.write(to: stagingDir.appendingPathComponent("sample.json"), options: [.atomic])

            // Rename staging dir into place atomically.
            let finalDir = root.appendingPathComponent(sampleID, isDirectory: true)
            try fm.moveItem(at: stagingDir, to: finalDir)

            lastWrite = LastWrite(timestamp: now, succeeded: true, message: nil)
        } catch let error as WriteError {
            lastWrite = LastWrite(timestamp: Date(), succeeded: false, message: error.description)
            throw error
        } catch {
            lastWrite = LastWrite(timestamp: Date(), succeeded: false, message: String(describing: error))
            throw WriteError.ioFailed(underlying: error)
        }
    }

    // MARK: - Clear

    public func clearAll() throws {
        guard fm.fileExists(atPath: root.path) else { return }
        try fm.removeItem(at: root)
        didInitDirs = false
    }

    // MARK: - Export

    /// Zips the entire EvalSamples directory into a tempdir file. Caller is
    /// responsible for sharing then deleting it.
    public func exportZip() throws -> URL {
        try ensureDirs()
        let stamp = Self.iso8601(Date()).replacingOccurrences(of: ":", with: "")
        let zipName = "eval-samples-\(stamp).zip"
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(zipName)
        try? fm.removeItem(at: dest)
        try fm.zipItem(at: root, to: dest, shouldKeepParent: true, compressionMethod: .deflate)
        return dest
    }

    // MARK: - Private

    private func ensureDirs() throws {
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            // Exclude from iCloud backup so book photos don't sync off-device.
            var url = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        if !fm.fileExists(atPath: templates.path) {
            try fm.createDirectory(at: templates, withIntermediateDirectories: true)
        }
        if !didInitDirs {
            // Wipe any leftover .in_progress/ from a crashed previous run.
            if fm.fileExists(atPath: staging.path) {
                try? fm.removeItem(at: staging)
            }
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            didInitDirs = true
        }
    }

    private func ensureTemplateFile(provider: LLMProvider, pageCount: Int, templateFile: String) throws {
        let target = templates.appendingPathComponent(templateFile)
        let inMemoryDict = Self.buildTemplate(provider: provider, pageCount: pageCount)
        let inMemoryBytes = try JSONSerialization.data(
            withJSONObject: inMemoryDict,
            options: [.sortedKeys]
        )

        if fm.fileExists(atPath: target.path) {
            let onDiskBytes = try Data(contentsOf: target)
            if SHA256.hash(data: onDiskBytes) != SHA256.hash(data: inMemoryBytes) {
                // Re-canonicalize on-disk JSON in case original was pretty-printed differently.
                if let onDiskObj = try? JSONSerialization.jsonObject(with: onDiskBytes),
                   let normalized = try? JSONSerialization.data(withJSONObject: onDiskObj, options: [.sortedKeys]),
                   SHA256.hash(data: normalized) == SHA256.hash(data: inMemoryBytes) {
                    return // semantically equal, formatting-only diff — OK
                }
                throw WriteError.templateMismatch(file: templateFile)
            }
            return
        }

        let pretty = try JSONSerialization.data(
            withJSONObject: inMemoryDict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try pretty.write(to: target, options: [.atomic])
    }

    private static func buildTemplate(provider: LLMProvider, pageCount: Int) -> [String: Any] {
        switch provider {
        case .claude: return ExtractionPrompts.Claude.requestTemplate(forPageCount: pageCount)
        case .gemini: return ExtractionPrompts.Gemini.requestTemplate(forPageCount: pageCount)
        }
    }

    private func sampleFolderURLs() throws -> [URL] {
        let kids = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return kids.filter { url in
            let name = url.lastPathComponent
            // Skip top-level dirs that aren't samples.
            if name == "request_templates" || name == ".in_progress" { return false }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    private static func sampleID(at date: Date) -> String {
        let ts = iso8601Compact(date)
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(12)
        return "\(ts)_\(suffix)"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func iso8601(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Filename-safe ISO8601: `YYYYMMDDTHHMMSSZ`.
    private static func iso8601Compact(_ date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    private static func encodeParsed(_ result: ExtractionResult) -> [String: Any] {
        let highlights = result.highlights.map { h -> [String: Any] in
            [
                "text": h.text,
                "page_number": h.pageNumber as Any? ?? NSNull(),
                "note": h.note as Any? ?? NSNull(),
            ]
        }
        return ["highlights": highlights]
    }
}

// MARK: - Image format sniffing

private struct ImageFormat {
    let label: String
    let fileExtension: String

    static let jpeg = ImageFormat(label: "jpeg", fileExtension: "jpg")
    static let heic = ImageFormat(label: "heic", fileExtension: "heic")
    static let png = ImageFormat(label: "png", fileExtension: "png")
    static let unknown = ImageFormat(label: "unknown", fileExtension: "bin")

    static func sniff(_ data: Data) -> ImageFormat {
        let prefix = data.prefix(12)
        if prefix.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if prefix.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        // HEIC starts with 4-byte size + "ftypheic" / "ftypheix" / "ftypmif1" etc.
        if prefix.count >= 12, prefix[4] == 0x66, prefix[5] == 0x74, prefix[6] == 0x79, prefix[7] == 0x70 {
            let brand = String(data: prefix[8..<12], encoding: .ascii) ?? ""
            if ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand) { return .heic }
        }
        return .unknown
    }

    /// Best-effort pixel size detection. Skipped for unknown formats.
    func pixelSize(of data: Data) -> (Int, Int)? {
        switch label {
        case "png":
            // IHDR width/height at bytes 16..23 (big-endian).
            guard data.count >= 24 else { return nil }
            let w = data.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            let h = data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            return (Int(w), Int(h))
        default:
            // Skip JPEG/HEIC pixel sniffing in v1 — Codex flagged it as nice-to-have
            // but the eval doesn't strictly need dimensions per-sample.
            return nil
        }
    }
}

#endif // EVAL_CAPTURE
