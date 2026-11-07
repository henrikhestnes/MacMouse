import AppKit
import Carbon
import Combine
import CoreGraphics
import CPrivate
import MacMouseCore

enum SystemActions {
    static func perform(_ action: SystemAction) {
        let notification = switch action {
        case .missionControl: "com.apple.expose.awake"
        case .appExpose: "com.apple.expose.front.awake"
        case .showDesktop: "com.apple.showdesktop.awake"
        }
        _ = CoreDockSendNotification(notification as CFString, 0)
    }

    private static let genericModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
    private static let sideSpecificModifiers = CGEventFlags(rawValue: UInt64(
        NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK | NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK |
            NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK | NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK))
    private static let keyboardModifiers = genericModifiers.union(sideSpecificModifiers)

    /// Presses a resolved shortcut the way LinearMouse's KeySimulator does: hardware-like key down
    /// and up events at the session tap, then a modifier event restoring the modifiers that were
    /// held during the scroll (`restoring`, the scroll event's flags).
    static func press(_ shortcut: ZoomShortcuts.Shortcut, restoring scrollFlags: CGEventFlags) {
        for keyDown in [true, false] {
            guard let event = hardwareLikeKeyEvent(shortcut.keyCode, keyDown: keyDown) else { continue }
            event.flags = event.flags.subtracting(keyboardModifiers).union(shortcut.modifierFlags)
            event.post(tap: .cgSessionEventTap)
        }
        restoreModifiers(scrollFlags.intersection(keyboardModifiers), afterUsing: shortcut.modifierFlags)
    }

    private static func restoreModifiers(_ restoring: CGEventFlags, afterUsing simulated: CGEventFlags) {
        let toRestore = restoring.intersection(genericModifiers).subtracting(simulated.intersection(genericModifiers))
        let toRelease = simulated.intersection(genericModifiers).subtracting(restoring.intersection(genericModifiers))
        let isRestoring = !toRestore.isEmpty
        guard isRestoring || !toRelease.isEmpty,
              let keyCode = modifierKeyCode(in: isRestoring ? restoring : simulated, matching: isRestoring ? toRestore : toRelease),
              let event = hardwareLikeKeyEvent(keyCode, keyDown: isRestoring) else { return }
        event.type = .flagsChanged
        event.flags = event.flags.subtracting(keyboardModifiers).union(restoring)
        event.post(tap: .cgSessionEventTap)
    }

    private static func modifierKeyCode(in flags: CGEventFlags, matching generic: CGEventFlags) -> CGKeyCode? {
        func side(_ right: Int32) -> Bool { flags.contains(CGEventFlags(rawValue: UInt64(right))) }
        if generic.contains(.maskShift) { return CGKeyCode(side(NX_DEVICERSHIFTKEYMASK) ? kVK_RightShift : kVK_Shift) }
        if generic.contains(.maskAlternate) { return CGKeyCode(side(NX_DEVICERALTKEYMASK) ? kVK_RightOption : kVK_Option) }
        if generic.contains(.maskControl) { return CGKeyCode(side(NX_DEVICERCTLKEYMASK) ? kVK_RightControl : kVK_Control) }
        if generic.contains(.maskCommand) { return CGKeyCode(side(NX_DEVICERCMDKEYMASK) ? kVK_RightCommand : kVK_Command) }
        return nil
    }

    /// A key event indistinguishable from a hardware press, as LinearMouse makes them.
    private static func hardwareLikeKeyEvent(_ keyCode: CGKeyCode, keyDown: Bool) -> CGEvent? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { return nil }
        event.timestamp = CGEventTimestamp(DispatchTime.now().uptimeNanoseconds)
        event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(source.keyboardType))
        return event
    }
}

/// Finds the keys behind ⌘+ and ⌘− on the current keyboard layout the way LinearMouse's
/// KeyEquivalentResolver does: by asking AppKit which main-row key, with ⌘ plus optional ⇧ and ⌥,
/// triggers a localized "+" or "-" menu key equivalent, skipping system shortcuts.
/// Resolved on the main thread; read from the event thread.
final class ZoomShortcuts: @unchecked Sendable {
    struct Shortcut: Equatable {
        let keyCode: CGKeyCode
        let modifierFlags: CGEventFlags
    }

    private let lock = NSLock()
    private var shortcuts: [String: Shortcut] = [:]
    private var generation = 0
    private var subscription: AnyCancellable?

    init() {
        let notifications = DistributedNotificationCenter.default()
        subscription = Publishers.Merge(
            notifications.publisher(for: .init(kTISNotifySelectedKeyboardInputSourceChanged as String)),
            notifications.publisher(for: .init(kTISNotifyEnabledKeyboardInputSourcesChanged as String)))
            // Never send a key resolved for the previous layout while AppKit catches up.
            .handleEvents(receiveOutput: { [weak self] _ in self?.invalidate() })
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func shortcut(zoomIn: Bool) -> Shortcut? {
        lock.withLock { shortcuts[zoomIn ? "+" : "-"] }
    }

    func refresh() {
        precondition(Thread.isMainThread)
        let current = lock.withLock { generation }
        let resolved = Self.resolve(["+", "-"])
        lock.withLock { if current == generation { shortcuts = resolved } }
    }

    private func invalidate() {
        lock.withLock {
            generation += 1
            shortcuts = [:]
        }
    }

    private final class Target: NSObject {
        var matched: String?
        @objc func match(_ item: NSMenuItem) { matched = item.representedObject as? String }
    }

    private static func resolve(_ equivalents: [String]) -> [String: Shortcut] {
        var hotKeys: Unmanaged<CFArray>?
        guard let source = CGEventSource(stateID: .privateState),
              CopySymbolicHotKeys(&hotKeys) == noErr,
              let entries = hotKeys?.takeRetainedValue() as? [[String: Any]] else { return [:] }
        let reserved = reservedShortcuts(in: entries)

        let target = Target()
        let menu = NSMenu(title: "MacMouse key equivalents")
        menu.autoenablesItems = false
        for (index, equivalent) in equivalents.enumerated() {
            let item = NSMenuItem(title: "__MacMouseKeyEquivalent_\(index)__", action: #selector(Target.match(_:)), keyEquivalent: equivalent)
            item.keyEquivalentModifierMask = .command
            item.allowsAutomaticKeyEquivalentLocalization = true
            item.allowsAutomaticKeyEquivalentMirroring = false
            item.target = target
            item.representedObject = equivalent
            item.isEnabled = true
            menu.addItem(item)
        }

        // Main typing keys, including ISO and JIS; never the numeric keypad.
        let keyCodes = Array(CGKeyCode(0)..<0x33) + [CGKeyCode(kVK_JIS_Yen), CGKeyCode(kVK_JIS_Underscore)]
        let modifierSets: [CGEventFlags] = [.maskCommand, [.maskCommand, .maskShift],
                                            [.maskCommand, .maskAlternate], [.maskCommand, .maskShift, .maskAlternate]]
        var result: [String: Shortcut] = [:]
        for modifiers in modifierSets {
            for keyCode in keyCodes {
                let shortcut = Shortcut(keyCode: keyCode, modifierFlags: modifiers)
                guard !reserved.contains(shortcut),
                      let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { continue }
                event.flags = modifiers
                event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(source.keyboardType))
                guard let nsEvent = NSEvent(cgEvent: event) else { continue }
                target.matched = nil
                // Dispatches only to this detached menu; nothing is posted to macOS.
                guard menu.performKeyEquivalent(with: nsEvent), let equivalent = target.matched,
                      equivalents.contains(equivalent), result[equivalent] == nil else { continue }
                result[equivalent] = shortcut
                if result.count == equivalents.count { return result }
            }
        }
        return result
    }

    private static func reservedShortcuts(in entries: [[String: Any]]) -> [Shortcut] {
        entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? UInt16,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? UInt32 else { return nil }
            var flags: CGEventFlags = []
            for (carbon, cg): (Int, CGEventFlags) in [(cmdKey, .maskCommand), (shiftKey, .maskShift),
                                                      (optionKey, .maskAlternate), (controlKey, .maskControl)]
                where modifiers & UInt32(carbon) != 0 {
                flags.insert(cg)
            }
            return Shortcut(keyCode: code, modifierFlags: flags)
        }
    }
}
