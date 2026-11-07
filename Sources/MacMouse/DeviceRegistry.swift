import Foundation

/// Which HID services are pointing devices and which of them the settings apply to, shared
/// between the main thread (which refreshes it) and the event thread (which reads it).
///
/// Events are attributed to a device by their HID sender ID, like LinearMouse. Events without
/// one, such as those other apps post, belong to the pointing device that was used last.
final class DeviceRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var pointerIDs: Set<UInt64> = []
    private var matchedIDs: Set<UInt64> = []
    private var lastActive: UInt64?

    func replace(pointerIDs: Set<UInt64>, matchedIDs: Set<UInt64>) {
        lock.withLock {
            self.pointerIDs = pointerIDs
            self.matchedIDs = matchedIDs
            if let lastActive, !pointerIDs.contains(lastActive) { self.lastActive = nil }
        }
    }

    /// Whether events from `sender` get the settings.
    func matches(sender: UInt64?) -> Bool {
        lock.withLock {
            if let sender, pointerIDs.contains(sender) { return matchedIDs.contains(sender) }
            return lastActive.map(matchedIDs.contains) ?? false
        }
    }

    func isKnown(_ sender: UInt64) -> Bool {
        lock.withLock { pointerIDs.contains(sender) }
    }

    /// Records input from a pointing device.
    func markActive(_ sender: UInt64) {
        lock.withLock {
            if pointerIDs.contains(sender) { lastActive = sender }
        }
    }
}
