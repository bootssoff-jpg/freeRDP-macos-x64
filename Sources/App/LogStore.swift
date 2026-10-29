import Foundation

final class LogStore {
    static let shared = LogStore()

    struct Entry {
        let date: Date
        let level: Int
        let message: String
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 5000
    private let writeQueue = DispatchQueue(label: "com.rdpmac.log-writer", qos: .utility)
    private let fileURL: URL
    private let dateFormatter: DateFormatter

    var onChange: (() -> Void)?

    private init() {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("RDPMac", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/RDPMac")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        fileURL = logs.appendingPathComponent("rdp.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        rotateIfNeeded()
    }

    func append(_ message: String, level: Int = 0) {
        let entry = Entry(date: Date(), level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        let line = "[\(dateFormatter.string(from: entry.date))] [\(levelName(level))] \(message)\n"
        writeQueue.async { [fileURL] in
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }

        if Thread.isMainThread {
            onChange?()
        } else {
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        }
    }

    func levelName(_ level: Int) -> String {
        switch level {
        case 1: return "WARN"
        case 2: return "ERROR"
        default: return "INFO"
        }
    }

    func text() -> String {
        entries.map { entry in
            "[\(dateFormatter.string(from: entry.date))] [\(levelName(entry.level))] \(entry.message)"
        }.joined(separator: "\n")
    }

    func exportText() -> String {
        let header = """
        RDP Mac — журнал подключений
        Содержимое буфера обмена и пароли в журнал не записываются.

        """
        return header + text() + "\n"
    }

    func export(to url: URL) throws {
        try exportText().write(to: url, atomically: true, encoding: .utf8)
    }

    func clear() {
        entries.removeAll()
        writeQueue.async { [fileURL] in
            try? Data().write(to: fileURL, options: .atomic)
        }
        onChange?()
    }

    var logFileURL: URL { fileURL }

    private func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 2 * 1024 * 1024 else { return }
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("rdp.log.1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
