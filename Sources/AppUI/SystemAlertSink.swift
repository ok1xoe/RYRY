// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import Foundation
import UserNotifications

/// Real sound (NSSound "Glass") and system notifications. A notification is only posted when the app is not active
/// and only from an .app bundle (outside one UserNotifications does not work). Permission is requested on demand.
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
            // the center is not captured (it is not Sendable) - it is fetched again in the handler
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }
}
