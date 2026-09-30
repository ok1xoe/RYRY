// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import Foundation
import Localization
import Observation
import Updates

/// State and actions of the updates window. It does not install anything: it downloads the DMG and opens it, the user drags the app over.
@MainActor @Observable
public final class UpdateModel {
    public enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case notConfigured
        case failed(String)
        case available(UpdateInfo)
        case systemTooOld(UpdateInfo)
        case downloading(UpdateInfo)
        case downloaded(URL)
        case downloadFailed(String)
    }

    public private(set) var status: Status = .idle
    /// Set by the app: opens the updates window.
    @ObservationIgnored public var showWindow: () -> Void = {}

    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private let network: UpdateNetwork
    @ObservationIgnored private let downloads: URL
    @ObservationIgnored private let opener: @MainActor (URL) -> Void
    @ObservationIgnored private var busy = false

    public init(checker: UpdateChecker? = nil, network: UpdateNetwork = URLSessionUpdateNetwork(),
                downloadsDirectory: URL? = nil, opener: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        let feed = Bundle.main.object(forInfoDictionaryKey: "MMUpdateFeedURL") as? String
        self.checker = checker ?? UpdateChecker(feedURL: feed, network: network, current: UpdateChecker.currentVersion())
        self.network = network
        self.downloads = downloadsDirectory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        self.opener = opener
    }

    /// Version of the currently running app (for the window's text).
    public var currentVersionText: String {
        let v = UpdateChecker.currentVersion()
        return v.description + (v.build.map { " (\($0))" } ?? "")
    }

    /// Check at startup: only when it is enabled and configured; the window opens only when there is a new version.
    public func checkAtLaunch(enabled: Bool) async {
        guard enabled, checker.isConfigured, !busy else { return }
        busy = true; defer { busy = false }
        if case .available(let info) = await checker.check(manual: false) {
            status = .available(info)
            showWindow()
        }
    }

    /// Manual command from the menu: the window always opens and shows the result.
    public func checkManually() async {
        showWindow()
        guard !busy else { return }
        busy = true; defer { busy = false }
        status = .checking
        switch await checker.check(manual: true) {
        case .notConfigured: status = .notConfigured
        case .upToDate, .skippedByLimit: status = .upToDate
        case .available(let i), .skippedVersion(let i): status = .available(i)
        case .systemTooOld(let i): status = .systemTooOld(i)
        case .failed(let m): status = .failed(m)
        }
    }

    public func download() async {
        guard case .available(let info) = status, !busy else { return }
        busy = true; defer { busy = false }
        status = .downloading(info)
        do {
            let f = try await UpdateChecker.download(info, to: downloads, network: network)
            status = .downloaded(f)
            opener(f)
        } catch {
            let m = (error as? UpdateError).map { e -> String in
                switch e {
                case .checksumMismatch: return L("kontrolní součet nesouhlasí")
                case .http(let c): return L("server odpověděl kódem %ld", c)
                case .invalidFeed(let s): return s
                }
            } ?? error.localizedDescription
            status = .downloadFailed(m)
        }
    }

    public func skipThisVersion() {
        if case .available(let info) = status { checker.skip(info) }
        status = .idle
    }

    public func later() { status = .idle }
}
