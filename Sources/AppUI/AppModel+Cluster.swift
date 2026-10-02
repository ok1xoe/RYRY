// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import Foundation
import Localization
import MacroEngine
import Settings
import Spots

/// DX cluster commands: the button macros (`settings.spots.clusterMacros`) and the manual line in the Spots window.
/// Sent to the cluster only (never to the radio); RBN does not accept commands.
extension AppModel {
    /// Variable context: with the engine, the same as transmit macros plus the rig frequency; without it, only calls and time.
    func clusterContext() async -> MacroContext {
        if let app { return await app.clusterMacroContext() }
        var c = MacroContext()
        c.myCall = settings.station.call.uppercased()
        c.hisCall = qso.call; c.name = qso.name; c.qth = qso.qth
        return c
    }

    static func clusterErrorText(_ e: Error) -> String {
        switch e as? ClusterCommandError {
        case .notConnected?: L("DX cluster není připojený nebo přihlášený – příkaz nebyl odeslán.")
        case .empty?: L("Prázdný příkaz.")
        case .tooLong?: L("Příkaz je příliš dlouhý (nejvýš %ld znaků).", ClusterCommand.maxLength)
        case .controlCharacter?: L("Příkaz obsahuje řídicí znaky.")
        case .incompleteSpot?: L("Spot (dx) potřebuje kmitočet v kHz i značku – příkaz nebyl odeslán.")
        case .sendFailed(let why)?: L("Příkaz clusteru se nepodařilo odeslat: %@", why)
        case nil: L("Příkaz clusteru selhal: %@", "\(e)")
        }
    }

    /// Sends a single manually entered line; true = sent. An error is stored in `clusterMessage`.
    @discardableResult
    public func sendClusterLine(_ text: String) async -> Bool {
        do {
            try await spotFeed.sendClusterCommand(text)
            clusterMessage = nil
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            clusterHistory.removeAll { $0 == clean }
            clusterHistory.append(clean)
            if clusterHistory.count > 30 { clusterHistory.removeFirst(clusterHistory.count - 30) }
            return true
        } catch {
            clusterMessage = Self.clusterErrorText(error)
            return false
        }
    }

    /// Runs a cluster macro: expands the variables (without the macro control characters), each line = one command. True = everything sent.
    @discardableResult
    public func runClusterMacro(_ i: Int) async -> Bool {
        guard settings.spots.clusterMacros.indices.contains(i) else { return false }
        let lines = MacroEngine.expandCluster(settings.spots.clusterMacros[i].text, context: await clusterContext())
        guard !lines.isEmpty else { clusterMessage = L("Prázdný příkaz."); return false }
        // check all the lines first (e.g. a spot without a call) so that only part of the macro is not sent
        for l in lines {
            do { _ = try ClusterCommand.validate(l) } catch { clusterMessage = Self.clusterErrorText(error); return false }
        }
        for l in lines {
            do { try await spotFeed.sendClusterCommand(l) } catch { clusterMessage = Self.clusterErrorText(error); return false }
        }
        clusterMessage = nil
        return true
    }
}
