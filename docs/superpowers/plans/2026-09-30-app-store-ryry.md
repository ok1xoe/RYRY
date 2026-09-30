# RYRY: Mac App Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship mmtty4mac to the Mac App Store as **RYRY**: sandboxed build, removed/replaced features that the sandbox forbids, new branding and icon, upload script, App Store Connect materials and the product website `ryry.ok1xoe.dev`.

**Architecture:** Same SwiftPM app, now always built with App Sandbox entitlements. Features that need to spawn processes (managed rigctld, tqsl CLI) or self-update are removed or replaced by sandbox-legal flows (TCP rigctld, ADIF hand-off to TQSL via NSWorkspace). File access outside the container goes through security-scoped bookmarks kept in the settings. Release = `xcodebuild -exportArchive` with `method=app-store-connect`.

**Tech Stack:** Swift 6 / SwiftPM, SwiftUI + AppKit, Swift Testing, Xcode 26 toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`), static HTML/CSS for the website.

**Spec:** `docs/superpowers/specs/2026-09-30-app-store-ryry-design.md`

## Global Constraints

- Distribution: **App Store only**; no DMG, no notarization scripts, no update checker.
- Bundle identifier stays `cz.ok1xoe.mmtty4mac`; `Application Support/mmtty4mac` stays; default log name stays `mmtty4mac`.
- User-visible product name: `RYRY`; App Store name `RYRY – RTTY for Contests`; subtitle `Sound-card RTTY based on MMTTY`.
- Copyright string: `© 2026 OK1XOE · LGPL v3 · based on MMTTY by JE3HHT`.
- Website: `https://ryry.ok1xoe.dev` (support `/support.html`, privacy `/privacy.html`, Czech under `/cs/`).
- Price: free. Category: Utilities. Languages: Czech + English.
- Minimum macOS stays 14.0.
- Every user-visible string goes through `L("<Czech key>")` with the English value in `Resources/Languages/en.json` and the Czech identity in `cs.json`.
- Build/test always with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A user upgrading from the DMG version with old settings (`rig.type = hamlibManaged`, `upload.lotwTqslPath`, `upload.lotwAuto`, `updates.*`, log folder in `~/Documents/mmtty4mac`) must start RYRY without errors, with a sensible fallback and one clear message. → tests in Task 2, 3, 4, 5.
2. The user cancels the "grant access to the log folder" dialog. The app must still start with a working log in the container, not crash, not lose the QSO being logged, and must say where the log is. → test in Task 5.
3. A stored folder bookmark is stale (folder moved or deleted). Re-prompt instead of writing into a path it cannot access. → test in Task 5.
4. TQSL is not installed. The ADIF must still be written to Downloads, with a clear message saying where it is and that TQSL is needed, and nothing marked as uploaded. → test in Task 3.
5. A "recent log" entry points to a folder without a bookmark. Prompt for access instead of failing with a POSIX error. → test in Task 5.

---

### Task 1: Sandbox entitlements and capability check

**Files:**
- Modify: `Resources/mmtty4mac.entitlements`
- Create: `docs/appstore/sandbox-check.md`

- [ ] **Step 1:** Replace the entitlements with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key><true/>
	<key>com.apple.security.device.audio-input</key><true/>
	<key>com.apple.security.device.serial</key><true/>
	<key>com.apple.security.network.client</key><true/>
	<key>com.apple.security.network.server</key><true/>
	<key>com.apple.security.files.user-selected.read-write</key><true/>
	<key>com.apple.security.files.bookmarks.app-scope</key><true/>
	<key>com.apple.security.files.downloads.read-write</key><true/>
</dict>
</plist>
```

- [ ] **Step 2:** Build with `MMTTY_ARCHS=arm64 ./scripts/make-app.sh` and run `codesign -d --entitlements - build/mmtty4mac.app`. Expected: all eight keys.
- [ ] **Step 3:** Launch the app, then verify in the running sandboxed app:
  - `ps` shows the process and `~/Library/Containers/cz.ok1xoe.mmtty4mac` exists,
  - the API answers with `curl -s -X POST http://127.0.0.1:7363` or `lsof -iTCP:7362 -sTCP:LISTEN`,
  - the DX cluster connects (Spots window),
  - with `rtty-tool`-style open of a serial port (`/dev/cu.Bluetooth-Incoming-Port`) through Settings → Rig → CAT, no "Operation not permitted",
  - the microphone prompt appears.

  Record each result in `docs/appstore/sandbox-check.md`.
- [ ] **Step 4:** Commit: `Sandbox entitlements for the Mac App Store`.

### Task 2: Remove the managed hamlib rig type

**Files:**
- Modify: `Sources/Settings/AppSettings.swift` (RigType, RigSettings decoding), `Sources/AppCore/RigFactory.swift`, `Sources/AppViews/SettingsView.swift` (rig section)
- Delete: `Sources/RigControl/ManagedHamlibRig.swift`, `Tests/RigControlTests/ManagedHamlibTests.swift`
- Test: `Tests/SettingsTests/Plan13SettingsTests.swift`, new `Tests/SettingsTests/AppStoreMigrationTests.swift`

**Interfaces:** Produces: `RigType` = `none, hamlib, flrig, cat`; `hamlibModel` is removed.

- [ ] **Step 1: Failing test** in `AppStoreMigrationTests.swift`:

```swift
import Foundation
import Testing
@testable import Settings

private func load(_ json: String) throws -> (AppSettings, [String]) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let r = SettingsStore(directory: dir).load()
    return (r.0, r.warnings)
}

@Test func managedHamlibBecomesTCPRigctldWithAWarning() throws {
    let (s, w) = try load(#"{"rig":{"type":"hamlibManaged","serialPort":"/dev/cu.usb1","hamlibModel":3073}}"#)
    #expect(s.rig.type == .hamlib && s.rig.effectivePort == 4532 && s.rig.host == "127.0.0.1")
    #expect(w.contains { $0.contains("rigctld") })
}
```

- [ ] **Step 2:** Run `swift test --filter managedHamlibBecomesTCPRigctldWithAWarning`. Expected: FAIL (`hamlibManaged` still decodes).
- [ ] **Step 3: Implement.** Change `RigType` to `case none, hamlib, flrig, cat`. Remove `hamlibModel` (property, CodingKey, decode line). In `RigSettings.init(from:)`, decode the type from the raw string first:

```swift
if let raw = try? c.decodeIfPresent(String.self, forKey: .type), raw == "hamlibManaged" {
    type = .hamlib
    w?.add(L("Spouštění rigctld aplikací už není k dispozici (App Store). Spusťte rigctld sami, RYRY se k němu připojí na 127.0.0.1:4532."))
} else {
    type = c.tolerant(.type, x.type, w, s)
}
```

  (`w` is the `WarningSink`; if `L` is not visible in Settings, add `import Localization` and the dependency in `Package.swift`.) Remove the `.hamlibManaged` case from `RigFactory.make`, the SettingsView picker entry, the `rigctld`/`models` state, the model picker, and the description line. Delete `ManagedHamlibRig.swift` and its tests. In `Plan13SettingsTests.swift`, remove the `hamlibModel` expectations and replace the `hamlibManaged` JSON case with `"type":"cat"`. Add the new string to `cs.json` (identity) and `en.json`: `"You can no longer have the app launch rigctld (App Store). Start rigctld yourself; RYRY connects to it at 127.0.0.1:4532."`
- [ ] **Step 4:** Run `swift test`. Expected: all PASS.
- [ ] **Step 5:** Commit: `Remove the managed hamlib rig type (sandbox cannot spawn rigctld)`.

### Task 3: LoTW via hand-off to TQSL

**Files:**
- Modify: `Sources/Upload/Services.swift` (replace the TQSL process part), `Sources/Upload/Infrastructure.swift` (errors), `Sources/Settings/…` (UploadSettings: drop `lotwTqslPath`, `lotwAuto`), `Sources/AppUI/UploadCoordinator.swift`, `Sources/AppUI/AppModel.swift` (auto-upload, new confirm API), `Sources/AppViews/LogWindow.swift`, `Sources/AppViews/SettingsView.swift` (Online section)
- Test: `Tests/UploadTests/UploadTests.swift`, `Tests/AppUITests/UploadCoordinatorTests.swift`

**Interfaces:**
- Produces in `Upload`:

```swift
public struct LoTWExport: Sendable {
    public init(directory: URL, now: @escaping @Sendable () -> Date = Date.init)
    /// Writes the eligible QSOs to `<directory>/<logName>-lotw-<yyyyMMdd-HHmmss>.adi`; returns the file and the IDs.
    public func write(_ records: [QSORecord], logName: String) throws -> (file: URL, ids: [UUID], skipped: Int)
}
public protocol TQSLOpener: Sendable {
    /// Opens the file in TrustedQSL; false = TQSL is not installed.
    func open(_ file: URL) async -> Bool
}
```

- Produces in `AppUI`:

```swift
public struct LoTWHandoff: Sendable, Equatable { public var file: URL; public var ids: [UUID]; public var openedInTQSL: Bool }
// UploadCoordinator
public func prepareLoTW(settings: AppSettings, log: QSOLogStore, logName: String) async throws -> LoTWHandoff?
// AppModel
public var pendingLoTW: LoTWHandoff?            // drives the confirmation dialog
public func confirmLoTW(_ uploaded: Bool) async  // true = mark ids as uploaded to LoTW
```

- [ ] **Step 1: Failing tests** in `UploadTests.swift`. Replace the tqsl tests with:

```swift
@Test func lotwExportWritesADIFWithEligibleQSOs() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lotw-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let fixed = Date(timeIntervalSince1970: 1_790_000_000)
    let r = try LoTWExport(directory: dir, now: { fixed }).write([rec("OK1A"), rec("DL1B", band: nil)], logName: "cqww")
    #expect(r.file.lastPathComponent.hasPrefix("cqww-lotw-") && r.file.pathExtension == "adi")
    #expect(r.ids.count == 1 && r.skipped == 1)
    let text = try String(contentsOf: r.file, encoding: .utf8)
    #expect(text.contains("<CALL:4>OK1A") && !text.contains("DL1B"))
}
```

  (Adapt `rec(_:band:)` to the existing helper in the file. If it has no `band` parameter, add one with default `"20m"`.) In `UploadCoordinatorTests.swift`:

```swift
private struct FakeOpener: TQSLOpener { let ok: Bool; func open(_ file: URL) async -> Bool { ok } }

@Test func lotwWithoutTQSLStillWritesTheFileAndMarksNothing() async throws {
    let (log, dir) = try await logWith(["OK1A"])            // existing helper pattern in this file
    let c = UploadCoordinator(secrets: FakeSecrets(), tqsl: FakeOpener(ok: false), downloads: dir)
    let h = try #require(try await c.prepareLoTW(settings: settings { $0.upload.lotwEnabled = true }, log: log, logName: "x"))
    #expect(FileManager.default.fileExists(atPath: h.file.path) && !h.openedInTQSL)
    #expect(UploadSelection.pending(await log.records, target: .lotw).0.count == 1)   // nothing marked
}
```

- [ ] **Step 2:** Run the two tests. Expected: FAIL (types missing).
- [ ] **Step 3: Implement.**
  - Delete `ProcessResult`, `ProcessRunner`, `SystemProcessRunner`, `TQSLLocator`, `LoTWUploader` and `UploadError.tqslNotFound` / `.tqsl`.
  - Add `LoTWExport` (uses `UploadSelection.adif(eligible)`, filter `band != nil`, `DateFormatter` `yyyyMMdd-HHmmss` in UTC).
  - Add `WorkspaceTQSLOpener: TQSLOpener` in AppUI. It looks for the app via `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.arrl.trustedqsl")`, then via `urlsForApplications(toOpen: file)` filtered by name containing `tqsl` (case-insensitive), then `/Applications/TrustedQSL/tqsl.app`. It opens with `NSWorkspace.shared.open([file], withApplicationAt:configuration:)` and returns false when none is found.
  - `UploadCoordinator` loses `runner`/`isExecutable` and gains `tqsl: any TQSLOpener = WorkspaceTQSLOpener()` and `downloads: URL` (default `FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]`). `uploadPending(.lotw, …)` throws `UploadError.notConfigured(L("LoTW se nahrává přes TQSL – použijte Log → LoTW"))`. `prepareLoTW` requires `lotwEnabled`, returns nil when there is nothing pending, writes the file and calls the opener.
  - `AppModel`: LoTW is no longer part of the auto-upload after logging. `uploadPending(.lotw)` calls `prepareLoTW` and stores `pendingLoTW`, then the message:
    - opened: `L("ADIF pro LoTW je v TQSL (%@). Podepište a odešlete ho, pak potvrďte v RYRY.", file.lastPathComponent)`,
    - not opened: `L("TQSL nenalezen. ADIF pro LoTW je uložený v Stažených souborech: %@. Nainstalujte TrustedQSL a otevřete ho v něm.", file.lastPathComponent)`.

    `confirmLoTW(true)` calls `log.markUploaded(ids:target: .lotw)` and clears `pendingLoTW`.
  - `LogWindow`: when `pendingLoTW != nil`, show an alert `L("Odeslali jste spojení v TQSL do LoTW?")` with the buttons `L("Ano, označit jako nahraná")` / `L("Zatím ne")`.
  - `SettingsView` Online: remove the tqsl path row and the LoTW auto toggle. Remove `lotwLocation` too (TQSL asks for it itself). Add the caption `L("LoTW: RYRY připraví ADIF a otevře ho v TrustedQSL, kde ho podepíšete a odešlete.")`.
  - `UploadSettings` decoding ignores the old keys (they are not in CodingKeys; tolerant decoding already skips unknown keys, so the test from Task 2's file must include them and still load).
  - Add every new string to both language files.
- [ ] **Step 4:** Add to `AppStoreMigrationTests.swift`:

```swift
@Test func oldLoTWKeysAreIgnored() throws {
    let (s, _) = try load(#"{"upload":{"lotwEnabled":true,"lotwTqslPath":"/x/tqsl","lotwAuto":true,"lotwLocation":"Home"}}"#)
    #expect(s.upload.lotwEnabled)
}
```

  Run `swift test`. Expected: all PASS.
- [ ] **Step 5:** Commit: `LoTW: hand the ADIF to TrustedQSL instead of running tqsl`.

### Task 4: Remove the update checker and the DMG pipeline

**Files:**
- Delete: `Sources/Updates/`, `Tests/UpdatesTests/`, `Sources/AppUI/UpdateModel.swift`, `Sources/AppViews/UpdateWindow.swift`, `Tests/AppUITests/UpdateModelTests.swift`, `Tests/SettingsTests/UpdateSettingsTests.swift`, `scripts/make-dmg.sh`, `scripts/release.sh`, `build/appcast.json` (untracked; ignore)
- Modify: `Package.swift`, `Sources/MMTTY4MacApp/App.swift`, `Sources/AppViews/SettingsView.swift`, `Sources/AppUI/AppModel.swift` (`take(\.updates.autoCheck)`), `Sources/Settings/AppSettings.swift` (`updates` section), `Resources/Info.plist` (`MMUpdateFeedURL`), language files

- [ ] **Step 1:** Add to `AppStoreMigrationTests.swift`:

```swift
@Test func oldUpdateSettingsAreIgnored() throws {
    let (s, w) = try load(#"{"updates":{"autoCheck":false},"station":{"call":"OK1XOE"}}"#)
    #expect(s.station.call == "OK1XOE" && w.isEmpty)
}
```

- [ ] **Step 2:** Remove everything listed above: the `Updates` targets and dependencies in `Package.swift`, the `UpdateModel` state and menu item and `Window(… id: "update")` in `App.swift`, the settings toggle, the `updates` property of `AppSettings` (with its CodingKey) and `MMUpdateFeedURL`. Remove the strings used only by the updater from both language files. Find them with `grep` for each key in `Sources`: a key with no hits outside the deleted files goes.
- [ ] **Step 3:** Run `swift build && swift test`. Expected: PASS, including `oldUpdateSettingsAreIgnored` (unknown section skipped silently).
- [ ] **Step 4:** Commit: `Remove the update checker and the DMG/notarization scripts (App Store only)`.

### Task 5: Log folder access with security-scoped bookmarks

**Files:**
- Create: `Sources/Settings/FolderBookmarks.swift`, `Sources/AppUI/FolderAccess.swift`, `Sources/AppViews/FolderAccessPanel.swift`
- Modify: `Sources/Settings/AppSettings.swift` (LogSettings: `bookmarks`, default directory), `Sources/AppUI/AppModel.swift` (`startNow`, `switchLog`, `openLog`, `newLog`, `saveLogAs`), `Sources/AppViews/SettingsView.swift` (log folder chooser), `Sources/AppViews/FileActions.swift`, `Sources/MMTTY4MacApp/App.swift` (recent logs)
- Test: `Tests/SettingsTests/FolderBookmarksTests.swift`, `Tests/AppUITests/FolderAccessTests.swift`

**Interfaces:**

```swift
// Settings
public struct FolderBookmarks: Codable, Sendable, Equatable {
    public var entries: [String: Data]                 // standardized folder path → bookmark data
    public func bookmark(for path: String) -> Data?
    public mutating func set(_ data: Data, for path: String)
    public mutating func remove(_ path: String)
    public static func key(_ path: String) -> String    // URL(fileURLWithPath:).standardizedFileURL.path, no trailing slash
}
extension LogSettings { public var bookmarks: FolderBookmarks }   // stored, tolerant decode, default empty
public enum HomeDirectory { public static var real: String }      // getpwuid(getuid()).pw_dir, NSHomeDirectory() fallback
// default: LogSettings.directory = HomeDirectory.real + "/Documents/RYRY"

// AppUI
public protocol FolderAccessPrompt: Sendable {
    /// Ask the user to grant a folder (NSOpenPanel preset to `suggested`). nil = cancelled.
    @MainActor func requestFolder(suggested: URL, message: String) async -> URL?
}
public protocol BookmarkCodec: Sendable {
    func make(_ url: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, stale: Bool)
}
@MainActor public final class FolderAccess {
    public init(prompt: any FolderAccessPrompt, codec: any BookmarkCodec = SecurityScopedCodec(), sandboxed: Bool = FolderAccess.isSandboxed)
    public static var isSandboxed: Bool   // ProcessInfo env "APP_SANDBOX_CONTAINER_ID" != nil
    /// Returns a URL the app may use for `path` (and starts accessing it), asking the user when needed.
    /// nil = the user refused; `bookmarks` is updated in place.
    public func acquire(_ path: String, bookmarks: inout FolderBookmarks, message: String) async -> URL?
    public func stopAll()
}
```

- [ ] **Step 1: Failing tests** (`FolderAccessTests.swift`):

```swift
import Foundation
import Testing
@testable import AppUI
import Settings

@MainActor final class FakePrompt: FolderAccessPrompt {
    var answer: URL?; var asked: [URL] = []
    init(_ a: URL?) { answer = a }
    func requestFolder(suggested: URL, message: String) async -> URL? { asked.append(suggested); return answer }
}
struct FakeCodec: BookmarkCodec {
    var stale = false; var fail = false
    func make(_ url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ d: Data) throws -> (url: URL, stale: Bool) {
        if fail { throw CocoaError(.fileNoSuchFile) }
        return (URL(fileURLWithPath: String(decoding: d, as: UTF8.self)), stale)
    }
}

@Test @MainActor func noBookmarkAsksOnceAndRemembers() async {
    let p = FakePrompt(URL(fileURLWithPath: "/Users/x/Documents/mmtty4mac"))
    let fa = FolderAccess(prompt: p, codec: FakeCodec(), sandboxed: true)
    var b = FolderBookmarks()
    let u = await fa.acquire("/Users/x/Documents/mmtty4mac", bookmarks: &b, message: "m")
    #expect(u?.path == "/Users/x/Documents/mmtty4mac" && p.asked.count == 1)
    _ = await fa.acquire("/Users/x/Documents/mmtty4mac/", bookmarks: &b, message: "m")
    #expect(p.asked.count == 1)                                   // remembered, trailing slash ignored
}

@Test @MainActor func cancelReturnsNilAndStoresNothing() async {
    let fa = FolderAccess(prompt: FakePrompt(nil), codec: FakeCodec(), sandboxed: true)
    var b = FolderBookmarks()
    #expect(await fa.acquire("/Users/x/logs", bookmarks: &b, message: "m") == nil && b.entries.isEmpty)
}

@Test @MainActor func staleOrBrokenBookmarkAsksAgain() async {
    let p = FakePrompt(URL(fileURLWithPath: "/Users/x/logs"))
    var b = FolderBookmarks(); b.set(Data("/Users/x/logs".utf8), for: "/Users/x/logs")
    let fa = FolderAccess(prompt: p, codec: FakeCodec(fail: true), sandboxed: true)
    #expect(await fa.acquire("/Users/x/logs", bookmarks: &b, message: "m") != nil && p.asked.count == 1)
}

@Test @MainActor func notSandboxedNeverAsks() async {
    let p = FakePrompt(nil)
    var b = FolderBookmarks()
    let u = await FolderAccess(prompt: p, codec: FakeCodec(), sandboxed: false).acquire("/tmp/x", bookmarks: &b, message: "m")
    #expect(u?.path == "/tmp/x" && p.asked.isEmpty)
}
```

  and a `FolderBookmarksTests.swift` round trip. `LogSettings` with `bookmarks` encodes and decodes, the `entries` keys are normalized, and an old settings file without `bookmarks` loads with an empty map.
- [ ] **Step 2:** Run. Expected: FAIL (types missing).
- [ ] **Step 3: Implement.**
  - `FolderBookmarks`, `HomeDirectory`, `LogSettings.bookmarks` with a tolerant decode.
  - `SecurityScopedCodec` uses `url.bookmarkData(options: [.withSecurityScope], …)` and `URL(resolvingBookmarkData:options: [.withSecurityScope], bookmarkDataIsStale:)`.
  - `FolderAccess.acquire`:
    - not sandboxed → return the URL for the path,
    - otherwise, if the path is inside the container (`NSHomeDirectory()` prefix) → return it,
    - otherwise, a bookmark that resolves and is not stale → `startAccessingSecurityScopedResource()`, keep the URL in `active` and return it (for a stale one, re-make the bookmark from the resolved URL),
    - otherwise → prompt; on OK, make the bookmark, store it and start accessing,
    - on cancel → nil.
  - `FolderAccessPanel: FolderAccessPrompt` (AppViews) uses `NSOpenPanel` with `canChooseDirectories = true`, `canChooseFiles = false`, `canCreateDirectories = true`, `directoryURL = suggested`, `message = message` and `prompt = L("Povolit přístup")`.
  - `AppModel` owns `folderAccess` (injected via init with the panel as default from the app target, a fake in tests). Before creating `QSOLogStore` in `startNow` and in `switchLog`, call `acquire(settings.log.directory, bookmarks: &settings.log.bookmarks, message: L("RYRY potřebuje přístup ke složce s logem „%@“. Vyberte ji prosím.", name))`.
    - On nil, fall back to `NSHomeDirectory() + "/Documents/RYRY"` (container), create it, switch `settings.log.directory` to it and `note(L("Bez přístupu ke složce logu. Log se ukládá do %@ (Log → Zobrazit ve Finderu).", path))`.
    - Save the settings when bookmarks change.
  - `openLog` / `newLog` / `saveLogAs` use the folder of the chosen file with the same `acquire`. The panel preselects that folder, so the user confirms with one click.
  - Recent logs in `App.swift` go through `openLog`, so they are covered.
  - SettingsView log folder chooser: after `p.runModal() == .OK`, store the bookmark directly from `p.url`.
  - Add all strings to the language files.
- [ ] **Step 4:** Add an `AppModel`-level test using the existing `Fixture` with `FolderAccess(prompt: FakePrompt(nil), codec: FakeCodec(), sandboxed: true)` and a log directory `/nonexistent/elsewhere`. Expect that after `start()` the log directory is under `NSHomeDirectory()` and a message was noted. Run `swift test`. Expected: PASS.
- [ ] **Step 5:** Commit: `Keep access to the log folder in the sandbox with security-scoped bookmarks`.

### Task 6: Container migration from the DMG version

**Files:**
- Create: `Resources/container-migration.plist`
- Modify: `scripts/make-app.sh` (copy it), `docs/appstore/review-notes.md` is not affected

- [ ] **Step 1:** Create:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Move</key>
	<array>
		<string>${ApplicationSupport}/mmtty4mac</string>
		<string>${Library}/Preferences/cz.ok1xoe.mmtty4mac.plist</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2:** In `make-app.sh` add `cp Resources/container-migration.plist "$APP/Contents/Resources/"`.
- [ ] **Step 3: Verify.**
  1. Delete `~/Library/Containers/cz.ok1xoe.mmtty4mac` after backing it up to the scratchpad.
  2. Make sure `~/Library/Application Support/mmtty4mac/settings.json` exists. If not, create it from a backup copy.
  3. Launch the app.
  4. Expected: `~/Library/Containers/cz.ok1xoe.mmtty4mac/Data/Library/Application Support/mmtty4mac/settings.json` exists and the station call from the old settings is shown.

  Record the result in `docs/appstore/sandbox-check.md`.
- [ ] **Step 4:** Commit: `Migrate settings from the DMG version into the sandbox container`.

### Task 7: Rename to RYRY, help links, Info.plist

**Files:**
- Modify: `Resources/Info.plist`, `Sources/MMTTY4MacApp/App.swift`, `Sources/QSOLog/Cabrillo.swift`, `Sources/QSOLog/ADIF.swift`, `Sources/AppCore/Callbook.swift`, `Sources/APIServer/HTTPServer.swift`, `Sources/AppViews/LanguageSection.swift`, `Sources/AppViews/LogWindow.swift`, language files, tests that assert those strings

- [ ] **Step 1: Failing tests.** In the existing Cabrillo and ADIF tests, change the expectations to `CREATED-BY: RYRY` and `PROGRAMID` = `RYRY`. Run them: FAIL.
- [ ] **Step 2: Implement.**
  - `Info.plist`: `CFBundleName`/`CFBundleDisplayName` = `RYRY`; `NSHumanReadableCopyright` = `© 2026 OK1XOE · LGPL v3 · based on MMTTY by JE3HHT`; `NSMicrophoneUsageDescription` = `RYRY needs the audio input to receive RTTY from your radio.`; add `ITSAppUsesNonExemptEncryption` = `<false/>`; `CFBundleShortVersionString` = `1.0.0`.
  - Main window title `RYRY`; menu `L("O aplikaci RYRY")`, `L("Příručka RYRY")`.
  - About credits: the line becomes `L("RYRY © 2026 OK1XOE. Licence GNU LGPL v3, zdrojový kód: github.com/ok1xoe/mmtty4mac.")`.
  - Help menu: `L("Web RYRY")` → `https://ryry.ok1xoe.dev`, `L("Podpora")` → `https://ryry.ok1xoe.dev/support.html` (Czech UI: `/cs/support.html`), `L("Ochrana osobních údajů")` → `/privacy.html`.
  - Cabrillo `CREATED-BY: RYRY`, ADIF header `RYRY ADIF export` and `PROGRAMID` `RYRY`, callbook `agent=RYRY`/`prg=RYRY`, HTTP `Server: RYRY`, language export file `RYRY-language.json`, log export default name prefix `RYRY`.
  - Update the other user-visible strings in the language files that contain `mmtty4mac`, in both files. Keys are Czech sentences, so rename the key and all `L()` uses together.
- [ ] **Step 3:** Run `swift test`. Expected: PASS.
- [ ] **Step 4:** Commit: `Rename the product to RYRY; help links to ryry.ok1xoe.dev; version 1.0.0`.

### Task 8: Built-in demo signal

**Files:**
- Create: `Resources/demo-rtty.wav` (generated), `scripts/make-demo-wav.sh`
- Modify: `scripts/make-app.sh`, `Sources/MMTTY4MacApp/App.swift` (Help menu), language files

- [ ] **Step 1:** `scripts/make-demo-wav.sh` runs `swift build -c release --product rtty-tool` and `.build/release/rtty-tool gen "RYRY RYRY CQ TEST OK1XOE OK1XOE TEST\r\nOK1XOE DE DL1ABC DL1ABC K\r\nDL1ABC 599 001 001 TU OK1XOE TEST\r\n" Resources/demo-rtty.wav --noise 0.08 --seed 7`.
- [ ] **Step 2:** Verify with `.build/release/rtty-tool decode Resources/demo-rtty.wav`. Expected: the text decodes with CQ, both calls and 599 001.
- [ ] **Step 3:** `make-app.sh` copies the WAV. The Help menu gets `L("Přehrát ukázkový signál")`, which calls `model.playWAV(Bundle.main.url(forResource: "demo-rtty", withExtension: "wav")!, speed: 1)`.
- [ ] **Step 4:** Build the app, run the menu item, confirm the text appears in RX (screenshot kept for Task 11).
- [ ] **Step 5:** Commit: `Built-in demo RTTY signal (Help → Play demo signal)`.

### Task 9: Icon (variant A, refined)

**Files:**
- Modify: `scripts/make-icon.swift`
- Create/Update: `Resources/AppIcon.icns`, `docs/appstore/icon-1024.png`, optionally `Resources/AppIcon.icon` + `Assets.car`

- [ ] **Step 1:** Refine the drawing:
  - body 824/1024 centered with a continuous-corner radius 185/1024, no own drop shadow,
  - waterfall 14 columns × 9 rows,
  - mark/space traces 2 columns wide with alternating bits,
  - spectrum line 2.2 % of size wide with 2 clear peaks over the traces,
  - brand-compatible cyan accent `#34E2E8` for the spectrum, instead of green.

  Output all `iconset` sizes plus a 1024 PNG.
- [ ] **Step 2:** Run `swift scripts/make-icon.swift`, look at 16, 32, 128 and 1024 px, and adjust until the traces and peaks are visible at 32 px.
- [ ] **Step 3:** Try `xcrun actool` with an `.icon` (Icon Composer format) for macOS 26. If it compiles, ship `Assets.car` + `CFBundleIconName`, keeping `.icns` as a fallback. If not, keep `.icns` and note it in `docs/appstore/README.md`.
- [ ] **Step 4:** Commit: `Icon: refined waterfall-and-spectrum design for RYRY`.

### Task 10: App Store build and upload script

**Files:**
- Create: `scripts/release-appstore.sh`
- Modify: `scripts/make-app.sh` (identity order: Apple Development first; Developer ID path removed), `docs/distribution.md` (rewrite)

- [ ] **Step 1:** `release-appstore.sh`:

```zsh
#!/bin/zsh
# Builds RYRY and uploads it to App Store Connect (or only exports the .pkg with --export-only).
# Needs: Xcode signed in to the team account; TEAM_ID in the environment; the app record in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[[ -n "${TEAM_ID:-}" ]] || { echo "TEAM_ID is not set (developer.apple.com → Membership)." >&2; exit 1; }
DEST=upload; [[ "${1:-}" == "--export-only" ]] && DEST=export
./scripts/make-app.sh
APP=build/mmtty4mac.app
V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
B=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
A=build/RYRY.xcarchive
rm -rf "$A" build/appstore; mkdir -p "$A/Products/Applications"
cp -R "$APP" "$A/Products/Applications/"
cat > "$A/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ApplicationProperties</key><dict>
    <key>ApplicationPath</key><string>Applications/mmtty4mac.app</string>
    <key>Architectures</key><array><string>arm64</string><string>x86_64</string></array>
    <key>CFBundleIdentifier</key><string>cz.ok1xoe.mmtty4mac</string>
    <key>CFBundleShortVersionString</key><string>$V</string>
    <key>CFBundleVersion</key><string>$B</string>
    <key>Team</key><string>$TEAM_ID</string>
  </dict>
  <key>ArchiveVersion</key><integer>2</integer>
  <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
  <key>Name</key><string>RYRY</string>
  <key>SchemeName</key><string>RYRY</string>
</dict></plist>
PL
OPTS=build/export-appstore.plist
cat > "$OPTS" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$DEST</string>
</dict></plist>
PL
xcodebuild -exportArchive -archivePath "$A" -exportOptionsPlist "$OPTS" -exportPath build/appstore -allowProvisioningUpdates
if [[ "$DEST" == export ]]; then
  PKG=$(ls build/appstore/*.pkg)
  echo "Package: $PKG"; pkgutil --check-signature "$PKG" || true
else
  echo "Uploaded $V ($B). Continue in App Store Connect → TestFlight / App Store."
fi
```

- [ ] **Step 2:** `make-app.sh`: remove the Developer ID branch (no notarization), prefer `Apple Development`, keep `SIGN_ID` override and ad-hoc fallback. Keep the universal default.
- [ ] **Step 3:** Run `TEAM_ID=GN8G426WK4 ./scripts/release-appstore.sh --export-only`. Expected: a `.pkg` in `build/appstore/`. If signing fails because the App ID or the distribution certificate is missing, record the exact error and the manual fix in `docs/appstore/README.md` (it needs the user's account). No upload is done in this task.
- [ ] **Step 4:** Rewrite `docs/distribution.md`: dev builds, App Store release, the manual one-time steps, and what was removed and why.
- [ ] **Step 5:** Commit: `App Store release script; distribution docs`.

### Task 11: App Store Connect materials and screenshots

**Files:**
- Create: `docs/appstore/README.md` (the step-by-step submission checklist), `metadata-en.md`, `metadata-cs.md`, `review-notes.md`, `privacy.md`, `LICENSE-EULA.txt`, `scripts/appstore-screenshots.sh`, `docs/appstore/screenshots/{en,cs}/*.png`

- [ ] **Step 1:** Write the metadata:
  - name, subtitle, promotional text (≤ 170), description (≤ 4000),
  - keywords (≤ 100 chars, comma-separated, no spaces after commas, no name repetition),
  - What's New,
  - URLs: support `https://ryry.ok1xoe.dev/support.html`, marketing `https://ryry.ok1xoe.dev`, privacy `https://ryry.ok1xoe.dev/privacy.html`,
  - copyright, category Utilities, age rating answers (all "None" → 4+), price Free.

  Check the lengths with a small `awk`/`wc -m` in the step.
- [ ] **Step 2:** `review-notes.md`:
  - what RTTY is,
  - how to test without a radio: Help → Play demo signal, then watch decoding, click a callsign, log the QSO,
  - why the microphone, serial ports (optional, radio control), the local API server on 127.0.0.1:7362/7363 (logger integration) and the network client (DX cluster, callbooks with the user's own accounts) are needed,
  - no login required.
- [ ] **Step 3:** `privacy.md`: answer "Data Not Collected". The reasons: no analytics, and third-party services (QRZ, HamQTH, eQSL, Club Log, DX cluster) are contacted only with the user's own accounts and directly by the app; the developer receives nothing. Export compliance: standard HTTPS only (`ITSAppUsesNonExemptEncryption = NO`).
- [ ] **Step 4:** `LICENSE-EULA.txt`: a short custom license that says RYRY is distributed under GNU LGPL v3, with a link to the full text and to the source code. `README.md` explains pasting it into App Store Connect → App Information → License Agreement, and flags the LGPL/App Store point as something to confirm, not legal advice.
- [ ] **Step 5:** `scripts/appstore-screenshots.sh`: launch the built app with `-language en` / `-language cs`, resize the main window to 1440×900 points on a 2× display (or pass through `sips` to exactly 2880×1800), start the demo signal, and capture the main, Band map, Score, Spots and Log windows with `screencapture -l <windowid>` (window IDs via a small Swift `CGWindowListCopyWindowInfo` helper). Normalize every image to 2880×1800 on a neutral background. Run it and check the images visually.
- [ ] **Step 6:** Commit: `App Store Connect materials and screenshots`.

### Task 12: Website ryry.ok1xoe.dev

**Files:**
- Create: `site/` with `index.html`, `support.html`, `privacy.html`, `cs/index.html`, `cs/support.html`, `cs/privacy.html`, `manual/` (copy of `docs/html` with a small bridge stylesheet), `css/site.css` (copied from `~/EngetoAcademy/xoe-web/css/site.css`), `css/ryry.css` (product-specific additions), `js/site.js` (theme toggle + oscilloscope + shared header/footer for RYRY, adapted from xoe-web), `assets/fonts/*` (copied), `img/` (icon, screenshots), `README.md` (deploy), `deploy/nginx-ryry.conf.example`

- [ ] **Step 1:** Copy the design system files unchanged: `css/site.css` and `assets/fonts/*.woff2` from `xoe-web`.
- [ ] **Step 2:** Write `js/site.js` for RYRY:
  - theme (the same storage key `ok1xoe-theme`, so the preference is shared with ok1xoe.dev),
  - header: wordmark `RYRY` with the `pwr` LED, nav links Features / Support / Manual / Privacy / CS↔EN, the theme switch and `← OK1XOE.dev`,
  - footer back-panel,
  - the oscilloscope. Its trace draws an FSK signal (two alternating frequencies) instead of the generic sine.
- [ ] **Step 3:** `index.html`:
  - hero: kick LED "Mac App Store · Free", wordmark `RYRY`, claim `Sound-card RTTY for macOS — <b>based on MMTTY</b>, built for contests.`, CTAs "Download on the Mac App Store" (placeholder `href="#appstore"` until the App Store ID exists, documented in README) and "Read the manual",
  - readout strip: `45.45 Bd` / `170 Hz` / `9 contests` / `2 APIs`,
  - features as a module rack: decoder & AFC, contest (ESM, score, multipliers), band map & DX cluster, logging & ADIF/Cabrillo, rig control (CAT, rigctld, flrig), logger API (fldigi XML-RPC, JSON-RPC),
  - screenshots (faceplate frames), requirements, the "based on MMTTY / LGPL / source" note.
- [ ] **Step 4:** `support.html` (FAQ: no audio, PTT, rigctld, LoTW via TQSL, where logs are, the settings migration; contact e-mail; GitHub issues) and `privacy.html` (no data collected; what third-party services the user may configure; contact; date). Czech versions under `cs/`.
- [ ] **Step 5:** `manual/`: copy `docs/html` and add `manual/bridge.css`, which maps the manual's own stylesheet onto the site tokens (background, text, links in `--signal`, fonts). Link it after `style.css` in the copied `index.html` files via `sed`.
- [ ] **Step 6:** Serve locally with `python3 -m http.server 8090 -d site` and screenshot the index, support, privacy and manual pages in both themes in the browser. Check the phone width (390 px) for no horizontal scroll.
- [ ] **Step 7:** `site/README.md`: how to deploy on the same server pattern as xoe-web (host Nginx vhost `ryry.ok1xoe.dev` + certbot, static root), with `deploy/nginx-ryry.conf.example`. Also how to replace the App Store placeholder link once the app has an ID.
- [ ] **Step 8:** Commit: `Product website for ryry.ok1xoe.dev in the OK1XOE.dev instrument design`.

### Task 13: Manual, README, final verification

**Files:**
- Modify: `docs/manual.md`, `docs/prirucka.md`, `docs/html/{en,cs}/index.html` (product name, LoTW flow, rig types, no updates, sandbox/log folder), `README.md`, `docs/rulings.md` (a ruling: App Store only, what was removed and why)

- [ ] **Step 1:** Update the docs. In prose, `mmtty4mac` → `RYRY`, except where the text means the repository or the legacy settings folder.
- [ ] **Step 2:** Run the full `swift test`. Expected: all pass.
- [ ] **Step 3:** Build the universal sandboxed app. Repeat the Task 1 checks and the Task 5 folder flow (choose a folder, quit, relaunch: no prompt; move the folder away: prompt), the demo signal, and the LoTW hand-off with TQSL absent. Update `docs/appstore/sandbox-check.md`.
- [ ] **Step 4:** Commit: `Docs: RYRY, App Store edition`.
