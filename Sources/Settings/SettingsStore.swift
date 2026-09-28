// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import ModemKit

public enum SettingsError: Error, Equatable, Sendable { case io(String), badSlot(Int) }

public enum SettingsPaths {
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mmtty4mac")
    }
}

private func writeAtomically<T: Encodable>(_ value: T, to url: URL) throws {
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(value).write(to: url, options: .atomic)
    } catch { throw SettingsError.io("\(url.lastPathComponent): \(error)") }
}

/// settings.json – tolerantní načtení (nikdy nespadne), atomické uložení.
public final class SettingsStore: Sendable {
    public let url: URL
    public init(directory: URL = SettingsPaths.defaultDirectory) { url = directory.appendingPathComponent("settings.json") }

    public func load() -> (AppSettings, warnings: [String]) {
        guard let data = try? Data(contentsOf: url) else { return (AppSettings(), []) }
        let sink = WarningSink()
        let d = JSONDecoder(); d.userInfo[.warnings] = sink
        do {
            let s = try d.decode(AppSettings.self, from: data)
            return (s, sink.all)
        } catch {
            return (AppSettings(), ["\(url.lastPathComponent) nelze přečíst (\(error.localizedDescription)); použito výchozí nastavení"])
        }
    }

    public func save(_ s: AppSettings) throws { try writeAtomically(s, to: url) }
}

public struct Profile: Codable, Sendable, Equatable {
    public var name: String
    public var rtty: [String: ParameterValue]
    public init(name: String, rtty: [String: ParameterValue]) { self.name = name; self.rtty = rtty }
}

/// 16 profilů parametrů modemu (jako UserPara.ini v MMTTY).
public final class ProfileStore: Sendable {
    public static let slotCount = 16
    public let url: URL
    public init(directory: URL = SettingsPaths.defaultDirectory) { url = directory.appendingPathComponent("profiles.json") }

    private struct File: Codable { var slots: [Profile?] }

    public func load() -> [Profile?] {
        var slots = (try? JSONDecoder().decode(File.self, from: Data(contentsOf: url)))?.slots ?? []
        if slots.count < Self.slotCount { slots += [Profile?](repeating: nil, count: Self.slotCount - slots.count) }
        return Array(slots.prefix(Self.slotCount))
    }

    public func save(_ p: Profile?, slot: Int) throws {
        guard (0..<Self.slotCount).contains(slot) else { throw SettingsError.badSlot(slot) }
        var slots = load()
        slots[slot] = p
        try writeAtomically(File(slots: slots), to: url)
    }
}
