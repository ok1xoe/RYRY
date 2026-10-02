// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Continuous recording of the received text into a file (MMTTY "Log Rx file"): one file per UTC day
/// `rx-YYYY-MM-DD.txt`, optionally with a UTC timestamp at the start of every line.
public final class RxTextLog {
    /// Conversion of the received text into file lines (CR is discarded, LF ends a line).
    public struct Formatter: Sendable {
        public var timestamps: Bool
        var atLineStart = true
        public init(timestamps: Bool) { self.timestamps = timestamps }

        public mutating func format(_ s: String, at date: Date) -> String {
            var out = ""
            for ch in s where ch != "\r" {
                if ch == "\n" || ch == "\r\n" { out.append("\n"); atLineStart = true; continue }
                if atLineStart, timestamps { out += RxTextLog.time.string(from: date) + " " }
                atLineStart = false
                out.append(ch)
            }
            return out
        }
    }

    static let time: DateFormatter = fmt("HH:mm:ss")
    static let day: DateFormatter = fmt("yyyy-MM-dd")
    static func fmt(_ f: String) -> DateFormatter {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = TimeZone(identifier: "UTC"); d.dateFormat = f; return d
    }

    public let directory: URL
    public var timestamps: Bool { formatter.timestamps }
    private var formatter: Formatter
    private var handle: FileHandle?
    private var currentDay = ""

    public init(directory: URL, timestamps: Bool) {
        self.directory = directory; formatter = Formatter(timestamps: timestamps)
    }

    public func fileURL(for date: Date) -> URL { directory.appendingPathComponent("rx-\(Self.day.string(from: date)).txt") }

    public func append(_ s: String, at date: Date = Date()) throws {
        let d = Self.day.string(from: date)
        if d != currentDay || handle == nil {
            close()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = fileURL(for: date)
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let h = try FileHandle(forWritingTo: url)
            try h.seekToEnd()
            handle = h; currentDay = d; formatter.atLineStart = true
        }
        let text = formatter.format(s, at: date)
        if !text.isEmpty { try handle?.write(contentsOf: Data(text.utf8)) }
    }

    public func close() { try? handle?.close(); handle = nil }
    deinit { close() }
}
