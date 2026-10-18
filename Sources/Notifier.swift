import AppKit
import os
import UserNotifications

private let log = Logger(subsystem: "com.voskvitsov.HayFutbol", category: "notifications")

/// Posts a notification when the verdict flips between blocked and clear.
///
/// The last verdict lives in UserDefaults rather than memory, so a Mac switched
/// on mid-match still hears that blocking started. Errors never count as a flip:
/// only successful checks are compared.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let enabledKey = "notificationsEnabled"
    private static let lastBlockedKey = "lastBlocked"
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        // Set before launch finishes, so a click on a notification that relaunched
        // the app is still delivered to us.
        center.delegate = self
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Asks at launch rather than at the first flip, so the prompt comes up while
    /// the user is looking, not in the middle of a match.
    func requestAuthorizationIfEnabled() {
        guard isEnabled else { return }
        Task { _ = await authorize() }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        guard enabled else { return }
        Task {
            // Switched on but refused at the system level: the switch alone would
            // do nothing, so show where the real one is.
            if !(await authorize()) {
                let pane = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
                NSWorkspace.shared.open(pane)
            }
        }
    }

    func update(with status: BlockStatus) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Self.lastBlockedKey) as? Bool
        // Recorded even while switched off, so switching back on does not report
        // a flip that happened long ago.
        defaults.set(status.blocked, forKey: Self.lastBlockedKey)
        // The very first verdict has nothing to flip from.
        guard isEnabled, let previous, previous != status.blocked else { return }

        let title = status.blocked ? "Blocking is on" : "Blocking is over"
        let body = status.blocked
            ? "\(status.blockedIPs) IPs blocked. Sites behind Cloudflare may not load."
            : "hayahora.futbol no longer sees widespread blocking."
        Task {
            guard await authorize() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // One identifier for both, so "over" replaces "on" in Notification
            // Center instead of a season's worth of them piling up.
            do {
                try await center.add(UNNotificationRequest(identifier: "block-status", content: content, trigger: nil))
                log.info("posted: \(title, privacy: .public)")
            } catch {
                log.error("post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Returns at once once the user has answered; only the first call prompts.
    private func authorize() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            log.info("authorized: \(granted)")
            return granted
        } catch {
            log.error("authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // An accessory app is rarely frontmost, but when it is (an alert of ours is
    // up), macOS would otherwise swallow the banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { _ = NSWorkspace.shared.open(StatusChecker.site) }
    }
}
