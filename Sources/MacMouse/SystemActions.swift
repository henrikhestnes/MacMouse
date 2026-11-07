import Carbon
import CoreGraphics
import CPrivate
import Foundation
import MacMouseCore

enum SystemActions {
    static func perform(_ action: SystemAction) {
        let notification = switch action {
        case .missionControl: "com.apple.expose.awake"
        case .appExpose: "com.apple.expose.front.awake"
        case .showDesktop: "com.apple.showdesktop.awake"
        }
        // Leave the event tap callback before talking to the Dock.
        DispatchQueue.main.async { _ = CoreDockSendNotification(notification as CFString, 0) }
    }

    /// Presses ⌘+ or ⌘− using whichever key types + or − on the current keyboard layout.
    static func zoom(in zoomIn: Bool) {
        let fallback = zoomIn ? kVK_ANSI_KeypadPlus : kVK_ANSI_KeypadMinus
        let (keyCode, shift) = key(typing: zoomIn ? "+" : "-") ?? (CGKeyCode(fallback), false)
        var flags: CGEventFlags = shift ? [.maskCommand, .maskShift] : .maskCommand
        if (0x41...0x5C).contains(Int(keyCode)) { flags.insert(.maskNumericPad) }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// The key that types `character`, preferring one without shift.
    private static func key(typing character: String) -> (CGKeyCode, Bool)? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> (CGKeyCode, Bool)? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for shift in [false, true] {
                let modifiers = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
                for code in 0..<128 {
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers,
                                                UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                                                &deadKeys, characters.count, &length, &characters)
                    if status == noErr, length == 1, String(utf16CodeUnits: characters, count: 1) == character {
                        return (CGKeyCode(code), shift)
                    }
                }
            }
            return nil
        }
    }
}
