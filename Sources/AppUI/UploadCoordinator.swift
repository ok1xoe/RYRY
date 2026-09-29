// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Localization
import QSOLog
import Settings
import Upload

/// Propojení nastavení, Klíčenky a služeb: vybere dosud nenahraná spojení, nahraje je a zapíše stav do logu.
public struct UploadCoordinator: Sendable {
    public var http: any HTTPClient
    public var runner: any ProcessRunner
    public var secrets: any SecretStore
    public var isExecutable: @Sendable (String) -> Bool

    public init(http: any HTTPClient = URLSessionHTTPClient(), runner: any ProcessRunner = SystemProcessRunner(),
                secrets: any SecretStore = KeychainSecretStore(),
                isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.http = http; self.runner = runner; self.secrets = secrets; self.isExecutable = isExecutable
    }

    public static func isEnabled(_ t: UploadTarget, _ s: UploadSettings) -> Bool {
        switch t { case .lotw: return s.lotwEnabled; case .eqsl: return s.eqslEnabled; case .clublog: return s.clublogEnabled }
    }
    public static func isAuto(_ t: UploadTarget, _ s: UploadSettings) -> Bool {
        isEnabled(t, s) && (t == .lotw ? s.lotwAuto : t == .eqsl ? s.eqslAuto : s.clublogAuto)
    }

    private func secret(_ service: String, _ what: String) throws -> String {
        guard let v = secrets.get(service: service, account: SecretServices.account), !v.isEmpty else {
            throw UploadError.notConfigured(what)
        }
        return v
    }

    /// Nahraje nenahraná spojení z logu; vrací zprávu pro uživatele. Chyba = nic se neoznačí.
    public func uploadPending(_ t: UploadTarget, settings: AppSettings, log: QSOLogStore) async throws -> String {
        let u = settings.upload
        guard Self.isEnabled(t, u) else { throw UploadError.notConfigured(L("%@ není v Nastavení → Online zapnuto", t.title)) }
        let (eligible, missing) = UploadSelection.pending(await log.records, target: t)
        var suffix = missing > 0 ? " " + L("Bez pásma (přeskočeno): %ld.", missing) : ""
        guard !eligible.isEmpty else { return L("%@: žádná nenahraná spojení.", t.title) + suffix }
        let outcome: UploadOutcome
        switch t {
        case .lotw:
            outcome = try await LoTWUploader(runner: runner, tqslPath: u.lotwTqslPath.isEmpty ? nil : u.lotwTqslPath,
                                             location: u.lotwLocation, isExecutable: isExecutable).upload(eligible)
        case .eqsl:
            guard !u.eqslUser.isEmpty else { throw UploadError.notConfigured(L("uživatel eQSL")) }
            let pw = try secret(SecretServices.eqsl, L("heslo eQSL (Klíčenka)"))
            outcome = try await EQSLUploader(http: http, user: u.eqslUser, password: pw).upload(eligible)
        case .clublog:
            guard !u.clublogEmail.isEmpty else { throw UploadError.notConfigured(L("e-mail Club Log")) }
            guard !settings.station.call.isEmpty else { throw UploadError.notConfigured(L("značka stanice (Nastavení → Stanice)")) }
            let pw = try secret(SecretServices.clublog, L("heslo Club Log (Klíčenka)"))
            let key = try secret(SecretServices.clublogAPIKey, L("API klíč Club Log (Klíčenka)"))
            outcome = try await ClubLogUploader(http: http, email: u.clublogEmail, password: pw,
                                                callsign: settings.station.call.uppercased(), apiKey: key).upload(eligible)
        }
        do { try await log.markUploaded(ids: outcome.uploadedIDs, target: t) }
        catch { throw UploadError.notConfigured(L("Nahráno, ale stav se nepodařilo zapsat do logu: %@", "\(error)")) }
        return outcome.message + suffix
    }
}
