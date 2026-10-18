import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let interval: Duration = .seconds(600)

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let notifier = Notifier()
    private var poller: Task<Void, Never>?
    private var status: BlockStatus?
    private var lastError: Error?
    private var checking = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        render()
        notifier.requestAuthorizationIfEnabled()
        startPolling()

        // A lid closed through a whole match should not open on the status from
        // before kickoff. The short delay gives Wi-Fi time to reassociate.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startPolling(after: .seconds(5)) }
        }
    }

    // MARK: - Polling

    /// (Re)starts the loop: check after `delay`, then every 10 minutes. Failed
    /// checks retry sooner, backing off a minute at a time to the normal interval.
    private func startPolling(after delay: Duration = .zero) {
        poller?.cancel()
        poller = Task {
            try? await Task.sleep(for: delay)
            var failures = 0
            while !Task.isCancelled {
                failures = await check() ? 0 : failures + 1
                let wait = failures == 0 ? Self.interval : min(.seconds(60) * failures, Self.interval)
                try? await Task.sleep(for: wait)
            }
        }
    }

    /// Returns false if the check failed.
    private func check() async -> Bool {
        checking = true
        render()
        do {
            let result = try await StatusChecker.check()
            // A restarted loop has its own check in flight; let that one report.
            if Task.isCancelled { return true }
            status = result
            lastError = nil
            notifier.update(with: result)
        } catch {
            if Task.isCancelled { return true }
            lastError = error
        }
        checking = false
        render()
        return lastError == nil
    }

    // MARK: - Status item

    private func render() {
        guard let button = statusItem.button else { return }
        // Dimmed until the first answer, and whenever the latest one is stale.
        let dimmed = status == nil || lastError != nil
        button.image = Self.icon(blocked: status?.blocked ?? false, dimmed: dimmed, label: headline)
        button.toolTip = headline
    }

    private static func icon(blocked: Bool, dimmed: Bool, label: String) -> NSImage {
        var config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if blocked {
            config = config.applying(.init(paletteColors: [.systemRed]))
        }
        let symbol = NSImage(
            systemSymbolName: blocked ? "soccerball.inverse" : "soccerball",
            accessibilityDescription: label
        )!.withSymbolConfiguration(config)!

        // Red only when something is wrong; otherwise a template image, so it
        // sits in the menu bar like any other monochrome icon.
        let image = dimmed
            ? NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
                return true
            }
            : symbol
        image.isTemplate = !blocked
        image.accessibilityDescription = label
        return image
    }

    private var headline: String {
        guard let status else {
            return lastError == nil ? "Checking…" : "Couldn't reach hayahora.futbol"
        }
        if status.blocked {
            return "Blocking is on: \(status.blockedIPs) IPs blocked"
        }
        return status.blockedIPs == 0
            ? "No blocking right now"
            : "No widespread blocking (\(status.blockedIPs) IPs blocked)"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(info(headline))

        if let status, status.blockedIPs > 0 {
            for isp in status.perISP {
                let item = info("\(isp.name): \(isp.count)")
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }
        if checking {
            menu.addItem(info("Checking…"))
        } else if let lastError {
            menu.addItem(info("Last check failed: \(lastError.localizedDescription)"))
        }
        if let status {
            let time = status.checkedAt.formatted(date: .omitted, time: .shortened)
            menu.addItem(info("Updated at \(time)"))
        }

        menu.addItem(.separator())
        menu.addItem(action("Check Now", #selector(checkNow), key: "r"))
        menu.addItem(action("Open hayahora.futbol", #selector(openSite), key: "o"))
        menu.addItem(.separator())
        let notify = action("Notify When Blocking Starts or Ends", #selector(toggleNotifications))
        notify.state = notifier.isEnabled ? .on : .off
        menu.addItem(notify)
        let login = action("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func checkNow() {
        startPolling()
    }

    @objc private func openSite() {
        NSWorkspace.shared.open(StatusChecker.site)
    }

    @objc private func toggleNotifications() {
        notifier.setEnabled(!notifier.isEnabled)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            if #available(macOS 14, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            NSAlert(error: error).runModal()
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // NSApp holds its delegate weakly.
    withExtendedLifetime(delegate) { app.run() }
}
