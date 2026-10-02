# App Privacy and export compliance

## App Privacy (App Store Connect → App Privacy)

Answer: **Data Not Collected.**

Why this is accurate (Apple counts data as "collected" when it leaves the device in a way the developer or its
partners can access):
- RYRY has no analytics, no crash reporting SDK, no advertising and no server of its own.
- Everything stays on the Mac: the log, settings and received text. Passwords and API keys are in the macOS Keychain.
- Third-party services are used only when the user turns them on and enters their own account. RYRY then talks
  to the service directly; the developer receives nothing:
  - callbook lookups (QRZ.com, HamQTH) send the callsign being looked up,
  - log uploads (eQSL, Club Log) send the QSOs the user uploads,
  - DX cluster and Reverse Beacon Network (telnet) send the user's callsign as the login,
  - LoTW goes through the separate TrustedQSL app.
- The local API listens on 127.0.0.1 only (unless the user allows remote access in Settings).

If Apple asks about third-party services in review: they are optional, user-initiated and use the user's own
accounts; RYRY does not share data with them on its own.

## Export compliance

`Info.plist` contains `ITSAppUsesNonExemptEncryption = NO`. RYRY only uses the encryption built into macOS (HTTPS
through URLSession) to talk to web services. That is exempt, so App Store Connect does not ask again for each
build.

## Age rating

Answer "None" / "No" to every question → **4+**. There is no user-generated content shown to others, no web
browsing and no unrestricted internet content (DX cluster spots are short technical radio messages).
