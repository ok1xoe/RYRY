// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import Foundation
import UserNotifications

/// Skutečný zvuk (NSSound „Glass“) a systémová oznámení. Oznámení se posílá jen když aplikace není aktivní
/// a jen z balíčku .app (mimo něj UserNotifications nefunguje). Oprávnění se vyžádá až na požádání.
@MainActor public final class SystemAlertSink: AlertSink {
    public init() {}

    private var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    public func playSound() {
        (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
    }

    public func requestNotificationAuthorization() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    public func notify(title: String, body: String) {
        guard canNotify, !NSApplication.shared.isActive else { return }
        UNUserNotificationCenter.current().getNotificationSettings { @Sendable st in
            guard st.authorizationStatus == .authorized || st.authorizationStatus == .provisional else { return }
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body
            // centrum se nezachytává (není Sendable) – získá se znovu v obsluze
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }
}
