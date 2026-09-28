// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CRingBuffer

/// Lock-free SPSC ring buffer (jeden zapisovatel, jeden čtenář). Metody s ukazateli nealokují.
public final class RingBuffer: @unchecked Sendable {
    private let r: OpaquePointer

    public init(capacity: Int) { r = cring_create(capacity)! }
    deinit { cring_destroy(r) }

    public var available: Int { cring_available(r) }
    public var capacity: Int { cring_capacity(r) }

    @discardableResult
    public func write(_ p: UnsafePointer<Float>, count: Int) -> Int { cring_write(r, p, count) }
    public func read(_ p: UnsafeMutablePointer<Float>, count: Int) -> Int { cring_read(r, p, count) }

    @discardableResult
    public func write(_ a: [Float]) -> Int { a.withUnsafeBufferPointer { cring_write(r, $0.baseAddress, $0.count) } }
    public func read(into a: inout [Float], count: Int) -> Int {
        let n = min(count, a.count)
        return a.withUnsafeMutableBufferPointer { cring_read(r, $0.baseAddress, n) }
    }
    public func clear() { cring_clear(r) }
}
