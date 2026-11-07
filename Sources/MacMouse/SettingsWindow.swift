import AppKit
import MacMouseCore
import ServiceManagement
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(store: SettingsStore, accessibilityGranted: @escaping () -> Bool) {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(store: store, accessibilityGranted: accessibilityGranted)))
        window.title = "MacMouse Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let accessibilityGranted: () -> Bool
    @State private var launchAtLogin = LoginItem.isEnabled

    private let buttons: [(Int64, String)] = [(2, "Middle button"), (3, "Back button"), (4, "Forward button"), (5, "Button 6")]

    var body: some View {
        Form {
            if !accessibilityGranted() {
                Section {
                    HStack {
                        Label("MacMouse needs Accessibility access to change scrolling and buttons.",
                              systemImage: "exclamationmark.triangle.fill")
                        Spacer()
                        Button("Open Settings…") { LoginItem.openAccessibilitySettings() }
                    }
                }
            }
            Section("Pointer") {
                slider("Speed", value: $store.settings.pointerSpeed, in: 0...1, format: "%.2f")
                    .disabled(store.settings.disablePointerAcceleration)
                slider("Acceleration", value: $store.settings.pointerAcceleration,
                       in: MouseSettings.pointerAccelerationRange, format: "%.1f")
                    .disabled(store.settings.disablePointerAcceleration)
                Toggle("Disable pointer acceleration", isOn: $store.settings.disablePointerAcceleration)
            }
            Section {
                Toggle("Reverse vertical scrolling", isOn: $store.settings.reverseVertical)
                Toggle("Reverse horizontal scrolling", isOn: $store.settings.reverseHorizontal)
                linesPicker("Vertical distance", selection: $store.settings.verticalLines)
                linesPicker("Horizontal distance", selection: $store.settings.horizontalLines)
                Toggle("⌘ + scroll zooms in and out", isOn: $store.settings.commandScrollZooms)
            } header: {
                Text("Scroll Wheel")
            } footer: {
                Text("Applies to mouse wheels only. Trackpad scrolling is left alone.")
                    .foregroundStyle(.secondary)
            }
            Section("Buttons") {
                ForEach(buttons, id: \.0) { number, title in
                    Picker(title, selection: Binding(
                        get: { store.settings.action(forButton: number) },
                        set: { store.settings.setAction($0, forButton: number) })) {
                        ForEach(ButtonAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            Section {
                Toggle("Enabled", isOn: Binding(get: { store.enabled }, set: { store.enabled = $0 }))
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: { _ in
                    LoginItem.toggle()
                    launchAtLogin = LoginItem.isEnabled
                }))
                HStack {
                    Button("Restore Defaults") { store.restoreDefaults() }
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "v\(short) (\(build))"
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(String(format: format, value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private func linesPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            Text("System").tag(0)
            ForEach(1...MouseSettings.linesRange.upperBound, id: \.self) { lines in
                Text(lines == 1 ? "1 line" : "\(lines) lines").tag(lines)
            }
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login could not be changed"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// Launch at Login defaults to on, but only once, so turning it off sticks.
    static func enableOnFirstRun() {
        let key = "launchAtLoginConfigured"
        // Skip `swift run` binaries and translocated copies, whose paths would not survive a restart.
        let path = Bundle.main.bundlePath
        guard !UserDefaults.standard.bool(forKey: key), path.hasSuffix(".app"), !path.contains("/AppTranslocation/") else { return }
        if SMAppService.mainApp.status == .notRegistered, (try? SMAppService.mainApp.register()) == nil { return }
        UserDefaults.standard.set(true, forKey: key)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
