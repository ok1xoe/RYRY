// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Localization
import QSOLog
import Settings
import Upload

/// Ties settings, the Keychain and the services together: picks the QSOs not uploaded yet, uploads them and writes the status into the log.
public struct UploadCoordinator: Sendable {
    public var http: any HTTPClient
    public var secrets: any UploadSecretStore
    /// Opens the LoTW ADIF in TrustedQSL.
    public var tqsl: any TQSLOpener
    /// Where the ADIF for LoTW is written (the sandbox allows ~/Downloads, and TQSL can read it from there).
    public var downloads: URL

    public init(http: any HTTPClient = URLSessionHTTPClient(), secrets: any UploadSecretStore = UploadKeychainStore(),
                tqsl: any TQSLOpener = WorkspaceTQSLOpener(),
                downloads: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.http = http; self.secrets = secrets; self.tqsl = tqsl; self.downloads = downloads
    }

    public static func isEnabled(_ t: UploadTarget, _ s: UploadSettings) -> Bool {
        switch t { case .lotw: return s.lotwEnabled; case .eqsl: return s.eqslEnabled; case .clublog: return s.clublogEnabled }
    }
    public static func isAuto(_ t: UploadTarget, _ s: UploadSettings) -> Bool {
        // LoTW needs the user in TrustedQSL, so it is never automatic
        isEnabled(t, s) && (t == .lotw ? false : t == .eqsl ? s.eqslAuto : s.clublogAuto)
    }

    private func secret(_ service: String, _ what: String) throws -> String {
        guard let v = secrets.get(service: service, account: SecretServices.account), !v.isEmpty else {
            throw UploadError.notConfigured(what)
        }
        return v
    }

    /// Uploads the not-yet-uploaded QSOs from the log; returns a message for the user. On error nothing is marked.
    public func uploadPending(_ t: UploadTarget, settings: AppSettings, log: QSOLogStore) async throws -> String {
        let u = settings.upload
        guard Self.isEnabled(t, u) else { throw UploadError.notConfigured(L("%@ není v Nastavení → Online zapnuto", t.title)) }
        let (eligible, missing) = UploadSelection.pending(await log.records, target: t)
        let suffix = missing > 0 ? " " + L("Bez pásma (přeskočeno): %ld.", missing) : ""
        guard !eligible.isEmpty else { return L("%@: žádná nenahraná spojení.", t.title) + suffix }
        let outcome: UploadOutcome
        switch t {
        case .lotw:
            throw UploadError.notConfigured(L("LoTW se nahrává přes TrustedQSL – použijte v okně Log tlačítko L"))
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

    /// LoTW: writes the QSOs not uploaded yet into ~/Downloads and opens the file in TrustedQSL. Nothing is marked -
    /// only the user knows whether TQSL sent it (`AppModel.confirmLoTW`). nil = nothing to upload.
    public func prepareLoTW(settings: AppSettings, log: QSOLogStore, logName: String) async throws -> LoTWHandoff? {
        guard settings.upload.lotwEnabled else { throw UploadError.notConfigured(L("%@ není v Nastavení → Online zapnuto", UploadTarget.lotw.title)) }
        let (eligible, _) = UploadSelection.pending(await log.records, target: .lotw)
        guard !eligible.isEmpty else { return nil }
        let r = try LoTWExport(directory: downloads).write(eligible, logName: logName)
        return LoTWHandoff(file: r.file, ids: r.ids, openedInTQSL: await tqsl.open(r.file))
    }
}

/// The LoTW file waiting for the user's confirmation that TQSL sent it.
public struct LoTWHandoff: Sendable, Equatable {
    public var file: URL
    public var ids: [UUID]
    public var openedInTQSL: Bool
}
