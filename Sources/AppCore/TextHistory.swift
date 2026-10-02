// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Text (RX or TX) with indexes since the last clear; older data above the limit is discarded in batches.
/// Internally absolute positions are used (the `takeNew` cursors are absolute).
public final class TextHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var buf: [Character] = []
    private var offset = 0                    // absolute position of the first character in buf
    private var base = 0                      // absolute position of the last clear()
    private let limit: Int

    public init(limit: Int = 1 << 20) { self.limit = max(1, limit) }

    public func append(_ s: String) {
        lock.withLock {
            buf.append(contentsOf: s)
            if buf.count > limit + limit / 4 {          // trimming in batches (amortized O(1) per character)
                let drop = buf.count - limit
                buf.removeFirst(drop); offset += drop
            }
        }
    }

    /// Absolute number of characters since the start (unchanged by clear) – for detecting new text.
    public var absoluteEnd: Int { lock.withLock { offset + buf.count } }

    /// Length since the last clear() (fldigi text.get_rx_length).
    public var totalLength: Int { lock.withLock { offset + buf.count - base } }

    /// Characters [start, start+length) since the last clear() – what has already been trimmed is omitted.
    public func range(start: Int, length: Int) -> String {
        lock.withLock { absRange(start.addingReportingOverflow(base).partialValue, length) }
    }

    private func absRange(_ start: Int, _ length: Int) -> String {
        let end = offset + buf.count
        let lo = max(start, offset, base)
        let (sum, overflow) = start.addingReportingOverflow(max(0, length))
        let hi = min(overflow ? end : sum, end)
        guard lo < hi else { return "" }
        return String(buf[(lo - offset)..<(hi - offset)])
    }

    /// Text from the absolute `cursor` to the end; advances the cursor.
    public func takeNew(cursor: inout Int) -> String {
        lock.withLock {
            let end = offset + buf.count
            if cursor < base { cursor = base }
            let s = absRange(cursor, end - cursor)
            cursor = end
            return s
        }
    }

    public func clear() { lock.withLock { base = offset + buf.count } }
}
