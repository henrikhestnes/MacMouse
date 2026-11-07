import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let linearMouseBundleID = "com.lujjjh.LinearMouse"

    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var quitLinearMouseItem: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private let store = SettingsStore()
    private let pointer = PointerController()
    private let interceptor = EventInterceptor()
    private lazy var settingsWindow = SettingsWindowController(store: store) { [weak self] in
        self?.interceptor.isRunning ?? false
    }
    private var permissionTimer: Timer?
    private var pointerTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        LoginItem.enableOnFirstRun()

        interceptor.settings = { [store] in store.settings }
        interceptor.isActive = { [store] in store.enabled }
        store.onChange = { [weak self] in self?.applyPointer() }

        // Reconnected mice and System Settings reset the pointer values; reapply them. `apply`
        // writes only what differs, so this is cheap.
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, store.enabled else { return }
            pointer.apply(store.settings)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyPointer()
        }
        applyPointer()

        // Shows the system prompt once; the menu explains how to grant access if it is still missing.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) || !interceptor.start() {
            waitForPermission()
            settingsWindow.show()
        }
        refreshMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pointer.restore()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    private func applyPointer() {
        if store.enabled {
            pointer.apply(store.settings)
        } else {
            pointer.restore()
        }
        refreshMenu()
    }

    /// Accessibility access is granted in System Settings while the app runs, so poll until the tap can be created.
    private func waitForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), interceptor.start() else { return }
            timer.invalidate()
            permissionTimer = nil
            refreshMenu()
            store.objectWillChange.send()
        }
    }

    // MARK: Menu

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MacMouse")
        let menu = NSMenu()
        menu.autoenablesItems = false
        statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        permissionItem = item("Open Accessibility Settings…", #selector(openAccessibilitySettings), in: menu)
        quitLinearMouseItem = item("Quit LinearMouse", #selector(quitLinearMouse), in: menu)
        menu.addItem(.separator())
        enabledItem = item("Enabled", #selector(toggleEnabled), in: menu)
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        loginItem = item("Launch at Login", #selector(toggleLaunchAtLogin), in: menu)
        menu.addItem(withTitle: "Quit MacMouse", action: #selector(quit), keyEquivalent: "q").target = self
        menu.delegate = self
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, in menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        if store.enabled { pointer.apply(store.settings) }
        refreshMenu()
    }

    private var linearMouseRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.linearMouseBundleID).isEmpty
    }

    private func refreshMenu() {
        let status: String
        let healthy: Bool
        if !interceptor.isRunning {
            (status, healthy) = ("Needs Accessibility access", false)
        } else if linearMouseRunning {
            // Both apps reversing the wheel would cancel out.
            (status, healthy) = ("LinearMouse is also running", false)
        } else if !store.enabled {
            (status, healthy) = ("Paused", false)
        } else if pointer.mouseNames.isEmpty {
            (status, healthy) = ("No mouse connected", true)
        } else {
            (status, healthy) = ("Active · " + pointer.mouseNames.joined(separator: ", "), true)
        }
        statusLine.title = status
        permissionItem.isHidden = interceptor.isRunning
        quitLinearMouseItem.isHidden = !linearMouseRunning
        enabledItem.state = store.enabled ? .on : .off
        let login = SMAppService.mainApp.status
        loginItem.state = login == .enabled ? .on : login == .requiresApproval ? .mixed : .off
        statusItem.button?.appearsDisabled = !healthy
        statusItem.button?.toolTip = "MacMouse · \(status)"
    }

    @objc private func toggleEnabled() {
        store.enabled.toggle()
    }

    @objc private func showSettings() { settingsWindow.show() }

    @objc private func openAccessibilitySettings() { LoginItem.openAccessibilitySettings() }

    @objc private func quitLinearMouse() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Self.linearMouseBundleID) { app.terminate() }
        // LinearMouse restores the mouse's own values as it quits; apply ours afterwards.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.applyPointer() }
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.toggle()
        refreshMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
