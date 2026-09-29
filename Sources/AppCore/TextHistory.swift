// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Text (RX nebo TX) s indexy od posledního vymazání; starší data nad limit se zahazují po dávkách.
/// Interně se pracuje s absolutními pozicemi (kurzory `takeNew` jsou absolutní).
public final class TextHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var buf: [Character] = []
    private var offset = 0                    // absolutní pozice prvního znaku v buf
    private var base = 0                      // absolutní pozice posledního clear()
    private let limit: Int

    public init(limit: Int = 1 << 20) { self.limit = max(1, limit) }

    public func append(_ s: String) {
        lock.withLock {
            buf.append(contentsOf: s)
            if buf.count > limit + limit / 4 {          // ořez po dávkách (amortizovaně O(1) na znak)
                let drop = buf.count - limit
                buf.removeFirst(drop); offset += drop
            }
        }
    }

    /// Absolutní počet znaků od startu (nemění se při clear) – pro detekci nového textu.
    public var absoluteEnd: Int { lock.withLock { offset + buf.count } }

    /// Délka od posledního clear() (fldigi text.get_rx_length).
    public var totalLength: Int { lock.withLock { offset + buf.count - base } }

    /// Znaky [start, start+length) od posledního clear() – co už bylo oříznuto, vynechá.
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

    /// Text od absolutního `cursor` do konce; posune kurzor.
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
