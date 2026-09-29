// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Text (RX nebo TX) s absolutními indexy od startu; starší data nad limit se zahazují.
public final class TextHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var buf: [Character] = []
    private var offset = 0                    // absolutní index prvního znaku v buf
    private let limit: Int

    public init(limit: Int = 1 << 20) { self.limit = max(1, limit) }

    public func append(_ s: String) {
        lock.withLock {
            buf.append(contentsOf: s)
            if buf.count > limit {
                let drop = buf.count - limit
                buf.removeFirst(drop); offset += drop
            }
        }
    }

    public var totalLength: Int { lock.withLock { offset + buf.count } }

    /// Znaky [start, start+length) – co už bylo oříznuto, vynechá.
    public func range(start: Int, length: Int) -> String {
        lock.withLock {
            let end = offset + buf.count
            let lo = max(start, offset)
            let (sum, overflow) = start.addingReportingOverflow(max(0, length))
            let hi = min(overflow ? end : sum, end)
            guard lo < hi else { return "" }
            return String(buf[(lo - offset)..<(hi - offset)])
        }
    }

    /// Text od `cursor` do konce; posune kurzor.
    public func takeNew(cursor: inout Int) -> String {
        let end = totalLength
        let s = range(start: cursor, length: end - cursor)
        cursor = end
        return s
    }

    public func clear() { lock.withLock { offset += buf.count; buf.removeAll() } }
}
