// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
// The texts are compared against the Czech wording (the localization key) - the tests run in the base language.
import Foundation
import Testing
import QSOLog
import Settings
import Upload
@testable import AppUI

private struct Opener: TQSLOpener {
    let ok: Bool
    func open(_ file: URL) async -> Bool { ok }
}

@Test @MainActor func lotwHandoffWaitsForConfirmationThenMarks() async throws {
    let f = Fixture()
    f.configure = { $0.upload.lotwEnabled = true }
    let dl = f.dir.appendingPathComponent("dl")
    try FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
    f.model.uploader = UploadCoordinator(secrets: UploadMemoryStore(), tqsl: Opener(ok: true), downloads: dl)
    await f.model.start()
    var r = QSORecord(call: "DL1ABC", timeOn: Date()); r.frequency = 14_080_000
    try await f.model.app!.log!.append(r)
    let msg = await f.model.uploadPending(.lotw)
    #expect(msg?.contains("TQSL") == true)
    let h = try #require(f.model.pendingLoTW)
    #expect(h.openedInTQSL && h.ids == [r.id])
    #expect(await f.model.app!.log!.records.allSatisfy { !$0.isUploaded(.lotw) })
    await f.model.confirmLoTW(true)
    #expect(f.model.pendingLoTW == nil)
    #expect(await f.model.app!.log!.records.allSatisfy { $0.isUploaded(.lotw) })
    await f.model.stop()
}

@Test @MainActor func lotwHandoffWithoutTQSLSaysWhereTheFileIsAndDeclineMarksNothing() async throws {
    let f = Fixture()
    f.configure = { $0.upload.lotwEnabled = true }
    let dl = f.dir.appendingPathComponent("dl")
    try FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
    f.model.uploader = UploadCoordinator(secrets: UploadMemoryStore(), tqsl: Opener(ok: false), downloads: dl)
    await f.model.start()
    var r = QSORecord(call: "DL1ABC", timeOn: Date()); r.frequency = 14_080_000
    try await f.model.app!.log!.append(r)
    let msg = try #require(await f.model.uploadPending(.lotw))
    let h = try #require(f.model.pendingLoTW)
    #expect(msg.contains(h.file.lastPathComponent) && msg.contains("TrustedQSL"))
    await f.model.confirmLoTW(false)
    #expect(f.model.pendingLoTW == nil)
    #expect(await f.model.app!.log!.records.allSatisfy { !$0.isUploaded(.lotw) })
    await f.model.stop()
}
