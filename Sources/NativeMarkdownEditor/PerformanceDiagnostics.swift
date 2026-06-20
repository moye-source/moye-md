import Foundation

struct PerformanceDiagnosticSnapshot: Equatable {
    let lines: [String]
}

final class PerformanceDiagnostics {
    static let shared = PerformanceDiagnostics()

    private let lock = NSLock()
    private let writerQueue = DispatchQueue(label: "org.moyesource.moye.performance-diagnostics")
    private var enabled = true
    private var records: [PerformanceDiagnosticRecord] = []
    private let maximumRecordCount = 240
    private let maximumLogFileBytes = 512 * 1024
    private let persistentEventThresholdMilliseconds = 12.0
    private let logURL = PerformanceDiagnostics.defaultLogURL()

    private init() {}

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    var diagnosticLogPath: String {
        logURL.path
    }

    func setEnabled(_ isEnabled: Bool) {
        lock.lock()
        enabled = isEnabled
        if !isEnabled {
            records.removeAll()
        }
        lock.unlock()

        if !isEnabled {
            clearLogFile()
        }

        if isEnabled {
            record("diagnostics.enabled")
        }
    }

    func reset() {
        lock.lock()
        records.removeAll()
        lock.unlock()
        clearLogFile()
        record("diagnostics.reset")
    }

    func measure<T>(_ name: String, metadata: [String: String] = [:], _ body: () throws -> T) rethrows -> T {
        guard isEnabled else {
            return try body()
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let value = try body()
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1_000
            record(name, durationMilliseconds: duration, metadata: metadata)
            return value
        } catch {
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1_000
            var nextMetadata = metadata
            nextMetadata["error"] = String(describing: type(of: error))
            record(name, durationMilliseconds: duration, metadata: nextMetadata)
            throw error
        }
    }

    func record(_ name: String, durationMilliseconds: Double? = nil, metadata: [String: String] = [:]) {
        lock.lock()
        guard enabled else {
            lock.unlock()
            return
        }

        let record = PerformanceDiagnosticRecord(
            date: Date(),
            name: name,
            durationMilliseconds: durationMilliseconds,
            metadata: metadata
        )

        records.append(record)
        if records.count > maximumRecordCount {
            records.removeFirst(records.count - maximumRecordCount)
        }
        lock.unlock()

        persistIfUseful(record)
    }

    func snapshot(
        documentName: String,
        characterCount: Int,
        lineCount: Int,
        blockCount: Int,
        outlineCount: Int,
        viewMode: EditorViewMode,
        previewTheme: PreviewTheme
    ) -> PerformanceDiagnosticSnapshot {
        lock.lock()
        let currentRecords = records
        let currentEnabled = enabled
        lock.unlock()

        var lines: [String] = [
            "Moye Performance Report",
            "diagnostics_enabled: \(currentEnabled)",
            "document_name: \(documentName)",
            "characters: \(characterCount)",
            "lines: \(lineCount)",
            "blocks: \(blockCount)",
            "outline_items: \(outlineCount)",
            "view_mode: \(viewMode.rawValue)",
            "preview_theme: \(previewTheme.rawValue)",
            "diagnostic_log_path: \(diagnosticLogPath)",
            "records: \(currentRecords.count)",
        ]

        for record in currentRecords.suffix(80) {
            lines.append(record.description)
        }

        return PerformanceDiagnosticSnapshot(lines: lines)
    }

    private func persistIfUseful(_ record: PerformanceDiagnosticRecord) {
        if let duration = record.durationMilliseconds, duration < persistentEventThresholdMilliseconds {
            return
        }

        let line = record.description
        let logURL = logURL
        let maximumLogFileBytes = maximumLogFileBytes

        writerQueue.async {
            let fileManager = FileManager.default
            let directoryURL = logURL.deletingLastPathComponent()

            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                let data = Data((line + "\n").utf8)
                if !fileManager.fileExists(atPath: logURL.path) {
                    fileManager.createFile(atPath: logURL.path, contents: data)
                } else if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    defer {
                        try? fileHandle.close()
                    }
                    _ = try? fileHandle.seekToEnd()
                    fileHandle.write(data)
                }

                try Self.trimLogFileIfNeeded(at: logURL, maximumBytes: maximumLogFileBytes)
            } catch {
                // Diagnostics must never interrupt editing.
            }
        }
    }

    private func clearLogFile() {
        let logURL = logURL
        writerQueue.async {
            try? FileManager.default.removeItem(at: logURL)
        }
    }

    private static func trimLogFileIfNeeded(at url: URL, maximumBytes: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue > maximumBytes else {
            return
        }

        let data = try Data(contentsOf: url)
        let retainedBytes = max(maximumBytes / 2, 1)
        let suffix = data.suffix(retainedBytes)
        try Data(suffix).write(to: url, options: .atomic)
    }

    private static func defaultLogURL() -> URL {
        let baseURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Moye", isDirectory: true)
            .appendingPathComponent("performance.log")
    }
}

private struct PerformanceDiagnosticRecord {
    let date: Date
    let name: String
    let durationMilliseconds: Double?
    let metadata: [String: String]

    var description: String {
        var parts = [
            PerformanceDiagnosticRecord.formatter.string(from: date),
            name,
        ]

        if let durationMilliseconds {
            parts.append(String(format: "%.2fms", durationMilliseconds))
        }

        for key in metadata.keys.sorted() {
            guard let value = metadata[key] else {
                continue
            }
            parts.append("\(key)=\(value)")
        }

        return parts.joined(separator: " | ")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
