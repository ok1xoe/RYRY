// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Hlídá složku jazyků: po uložení upraveného souboru znovu načte aktivní jazyk (bez restartu aplikace).
public final class LanguageWatcher: @unchecked Sendable {
    let library: LanguageLibrary
    let localizer: Localizer
    let defaults: UserDefaults
    /// Fronta, na které se jazyk přepne (aplikace: hlavní – tam překresluje SwiftUI).
    let deliverOn: DispatchQueue
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "mmtty4mac.languages")

    public init(library: LanguageLibrary, localizer: Localizer = .shared, defaults: UserDefaults = .standard,
                deliverOn: DispatchQueue = .main) {
        self.library = library; self.localizer = localizer; self.defaults = defaults; self.deliverOn = deliverOn
    }

    public func start() {
        stop()
        try? FileManager.default.createDirectory(at: library.userDirectory, withIntermediateDirectories: true)
        fd = open(library.userDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        // zápis „atomic“ nahradí soubor přejmenováním → změna obsahu adresáře
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: queue)
        s.setEventHandler { [weak self] in self?.scheduleReload() }
        s.setCancelHandler { [fd] in close(fd) }
        source = s
        s.resume()
    }

    public func stop() {
        source?.cancel(); source = nil; fd = -1
        pending?.cancel(); pending = nil
    }

    deinit { stop() }

    /// Editory ukládají po částech – načíst až po krátké pauze.
    private func scheduleReload() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.reload() }
        pending = w
        queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: w)
    }

    func reload() {
        let code = localizer.code
        let p = library.pack(code: code)
        guard p != nil || code == Localizer.baseCode else { return }        // rozbitý soubor – ponechat současný jazyk
        let l = localizer
        deliverOn.async { if l.code == code { l.use(p) } }
    }
}
