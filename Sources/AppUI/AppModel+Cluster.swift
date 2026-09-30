// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Foundation
import Localization
import MacroEngine
import Settings
import Spots

/// Příkazy pro DX cluster: makra na tlačítkách (`settings.spots.clusterMacros`) a ruční řádek v okně Spoty.
/// Odesílá se jen do clusteru (nikdy do rádia); RBN příkazy nepřijímá.
extension AppModel {
    /// Kontext proměnných: s enginem jako vysílací makra + frekvence rigu; bez něj jen značky a čas.
    func clusterContext() async -> MacroContext {
        if let app { return await app.clusterMacroContext() }
        var c = MacroContext()
        c.myCall = settings.station.call.uppercased()
        c.hisCall = qso.call; c.name = qso.name; c.qth = qso.qth
        return c
    }

    static func clusterErrorText(_ e: Error) -> String {
        switch e as? ClusterCommandError {
        case .notConnected?: L("DX cluster není připojený – příkaz nebyl odeslán.")
        case .empty?: L("Prázdný příkaz.")
        case .tooLong?: L("Příkaz je příliš dlouhý (nejvýš %ld znaků).", ClusterCommand.maxLength)
        case .controlCharacter?: L("Příkaz obsahuje řídicí znaky.")
        case nil: L("Příkaz clusteru selhal: %@", "\(e)")
        }
    }

    /// Pošle jeden ručně zadaný řádek; true = odesláno. Chyba se uloží do `clusterMessage`.
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

    /// Spustí makro clusteru: expanduje proměnné (bez řídicích znaků maker), každý řádek = jeden příkaz. True = vše odesláno.
    @discardableResult
    public func runClusterMacro(_ i: Int) async -> Bool {
        guard settings.spots.clusterMacros.indices.contains(i) else { return false }
        let lines = MacroEngine.expandCluster(settings.spots.clusterMacros[i].text, context: await clusterContext())
        guard !lines.isEmpty else { clusterMessage = L("Prázdný příkaz."); return false }
        for l in lines {
            do { try await spotFeed.sendClusterCommand(l) } catch { clusterMessage = Self.clusterErrorText(error); return false }
        }
        clusterMessage = nil
        return true
    }
}
