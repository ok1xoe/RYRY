// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import Foundation

/// Spoken output for a screen reader (VoiceOver announcements). Replaceable in tests.
@MainActor public protocol SpeechAnnouncing: AnyObject {
    /// Speaks the text. `interrupts` = the operator asked for it (high priority), otherwise it is a background event.
    func announce(_ text: String, interrupts: Bool)
}

@MainActor public final class NullSpeechAnnouncer: SpeechAnnouncing {
    public init() {}
    public func announce(_ text: String, interrupts: Bool) {}
}

/// A real VoiceOver announcement. Without an assistive client the system drops it, so nothing changes for a sighted user.
@MainActor public final class SystemSpeechAnnouncer: SpeechAnnouncing {
    public init() {}
    public func announce(_ text: String, interrupts: Bool) {
        guard !text.isEmpty else { return }
        let element: Any = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp as Any
        let priority = interrupts ? NSAccessibilityPriorityLevel.high : .medium
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: priority.rawValue])
    }
}

/// Rate limit for spoken announcements. Speech is serial and slow, so an announcement only goes out when
/// (a) enough time has passed since the previous one, (b) the same event is not repeated too soon and
/// (c) the sliding window is not full - a burst of spots during a contest must not turn into a monologue.
/// Pure logic (no AppKit), the memory is bounded.
public struct AnnouncementLimiter: Sendable {
    public struct Policy: Sendable, Equatable {
        /// Minimum gap between two announcements (one announcement at a time).
        public var minGap: TimeInterval = 2.5
        /// The same key (the same station / the same event) is not repeated sooner than this.
        public var repeatGap: TimeInterval = 30
        /// The sliding window and how many announcements fit into it.
        public var window: TimeInterval = 60
        public var maxPerWindow = 8
        public init(minGap: TimeInterval = 2.5, repeatGap: TimeInterval = 30, window: TimeInterval = 60,
                    maxPerWindow: Int = 8) {
            self.minGap = minGap; self.repeatGap = repeatGap; self.window = window; self.maxPerWindow = maxPerWindow
        }
    }

    public var policy: Policy
    /// How many keys are remembered at most (a contest produces thousands of callsigns).
    public let maxKeys: Int
    private var lastByKey: [String: Date] = [:]
    private var recent: [Date] = []
    private var lastAt: Date?
    private var suppressed = 0

    public init(policy: Policy = Policy(), maxKeys: Int = 500) {
        self.policy = policy; self.maxKeys = max(1, maxKeys)
    }

    /// How many announcements have been dropped since the last one that was allowed.
    public var suppressedCount: Int { suppressed }
    public var keyCount: Int { lastByKey.count }

    /// nil = suppressed. Otherwise the number of announcements dropped since the previous allowed one
    /// (the caller can tell the operator "+N skipped").
    public mutating func allow(key: String, now: Date) -> Int? {
        recent.removeAll { now.timeIntervalSince($0) >= policy.window }
        let tooSoon = lastAt.map { now.timeIntervalSince($0) < policy.minGap } ?? false
        let repeated = lastByKey[key].map { now.timeIntervalSince($0) < policy.repeatGap } ?? false
        if tooSoon || repeated || recent.count >= policy.maxPerWindow {
            suppressed += 1
            return nil
        }
        lastAt = now
        recent.append(now)
        lastByKey[key] = now
        prune(now: now, keep: key)
        let dropped = suppressed
        suppressed = 0
        return dropped
    }

    /// Forgets the history (a new contest, the log was switched) - the next announcement goes out at once.
    public mutating func reset() {
        lastByKey = [:]; recent = []; lastAt = nil; suppressed = 0
    }

    private mutating func prune(now: Date, keep: String) {
        guard lastByKey.count > maxKeys else { return }
        lastByKey = lastByKey.filter { $0.key == keep || now.timeIntervalSince($0.value) < policy.repeatGap }
        guard lastByKey.count > maxKeys else { return }
        for (k, _) in lastByKey.sorted(by: { $0.value < $1.value }).prefix(lastByKey.count - maxKeys) where k != keep {
            lastByKey[k] = nil
        }
    }
}
