import AppKit
import CoreGraphics
import CPrivate
import MacMouseCore

/// Rewrites scroll wheel and extra-button events from the mice the settings apply to. Like
/// LinearMouse, it taps at the HID level, before other apps' session taps, on its own thread so
/// a busy main thread never delays input. Needs Accessibility access.
final class EventInterceptor: @unchecked Sendable {
    /// Applications whose posted events LinearMouse never touches.
    private static let bypassedSources: Set<String> = ["cc.ffitch.shottr", "com.superultra.Homerow"]

    private let registry: DeviceRegistry
    private let zoomShortcuts: ZoomShortcuts
    /// Called on the main thread when an event comes from a device not seen yet.
    var onUnknownDevice: () -> Void = {}

    private let lock = NSLock()
    private var settings = MouseSettings()
    private var enabled = true
    private var lastUnknownDeviceReport = -Double.infinity
    private var bypassCache: [pid_t: Bool] = [:]

    // Used only on the event thread.
    private var scroll = ScrollProcessor()
    private var buttons = ButtonMapper()
    private var zoomThrottle = ActionThrottle()

    private var tap: CFMachPort?
    private var activityTap: CFMachPort?

    var isRunning: Bool { tap != nil }

    init(registry: DeviceRegistry, zoomShortcuts: ZoomShortcuts) {
        self.registry = registry
        self.zoomShortcuts = zoomShortcuts
    }

    func update(settings: MouseSettings, enabled: Bool) {
        lock.withLock {
            self.settings = settings
            self.enabled = enabled
        }
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let mask = [CGEventType.scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
            .reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
                                              Unmanaged<EventInterceptor>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
                                          }, userInfo: userInfo) else { return false }
        // Pointer movement and clicks only mark the device as last used, so they are observed
        // without holding them up.
        let activityMask = [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                            .leftMouseDragged, .rightMouseDragged]
            .reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        let activityTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                            eventsOfInterest: activityMask, callback: { _, type, event, refcon in
                                                Unmanaged<EventInterceptor>.fromOpaque(refcon!).takeUnretainedValue().observe(type, event)
                                            }, userInfo: userInfo)
        self.tap = tap
        self.activityTap = activityTap
        let thread = Thread {
            for port in [tap, activityTap].compactMap({ $0 }) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
            }
            CFRunLoopRun()
        }
        thread.name = "MacMouse events"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    // MARK: Event thread

    private func observe(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let activityTap { CGEvent.tapEnable(tap: activityTap, enable: true) }
        } else if let sender = senderID(of: event) {
            noteSender(sender)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let (settings, enabled) = lock.withLock { (self.settings, self.enabled) }
        guard enabled else { return pass }
        let hidEvent = CGEventCopyIOHIDEvent(event)
        let sender = hidEvent.map { IOHIDEventGetSenderID($0) }
        if let sender { noteSender(sender, markActive: type == .otherMouseDown || type == .otherMouseUp) }
        let matches = !isBypassed(event) && registry.matches(sender: sender)

        switch type {
        case .scrollWheel:
            guard matches else { return pass }
            return handleScroll(event, hidEvent, settings) ? pass : nil
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            let phase: ButtonPhase = type == .otherMouseDown ? .down : type == .otherMouseUp ? .up : .dragged
            let modifiersHeld = !event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).isEmpty
            switch buttons.process(button: event.getIntegerValueField(.mouseEventButtonNumber), phase: phase,
                                   modifiersHeld: modifiersHeld, matchesDevice: matches, settings: settings) {
            case .pass:
                return pass
            case let .remap(number):
                event.setIntegerValueField(.mouseEventButtonNumber, value: number)
                return pass
            case .swallow:
                return nil
            case let .perform(action):
                SystemActions.perform(action)
                return nil
            }
        default:
            return pass
        }
    }

    /// Returns false to swallow the event.
    private func handleScroll(_ event: CGEvent, _ hidEvent: IOHIDEvent?, _ settings: MouseSettings) -> Bool {
        func axis(_ lines: CGEventField, _ fixed: CGEventField, _ points: CGEventField, _ hid: IOHIDEventField) -> ScrollAxis {
            ScrollAxis(lines: event.getIntegerValueField(lines), fixed: event.getDoubleValueField(fixed),
                       points: event.getDoubleValueField(points), hid: hidEvent.map { IOHIDEventGetFloatValue($0, hid) } ?? 0)
        }
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let input = ScrollEvent(
            vertical: axis(.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1, MMIOHIDEventFieldScrollY),
            horizontal: axis(.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2, MMIOHIDEventFieldScrollX),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhaseBegan: event.getIntegerValueField(.scrollWheelEventScrollPhase) == Int64(CGScrollPhase.began.rawValue),
            isMomentum: momentum != Int64(CGMomentumScrollPhase.none.rawValue),
            momentumEnded: momentum == Int64(CGMomentumScrollPhase.end.rawValue),
            command: event.flags.contains(.maskCommand))
        switch scroll.process(input, settings: settings) {
        case .pass:
            return true
        case .swallow:
            return false
        case let .rewrite(writes):
            for write in writes { apply(write, to: event, hidEvent) }
            return true
        case let .zoom(zoomIn):
            if let shortcut = zoomShortcuts.shortcut(zoomIn: zoomIn),
               zoomThrottle.allows(at: ProcessInfo.processInfo.systemUptime) {
                SystemActions.press(shortcut, restoring: event.flags)
            }
            return false
        }
    }

    private func apply(_ write: ScrollWrite, to event: CGEvent, _ hidEvent: IOHIDEvent?) {
        func fields(_ axis: ScrollAxisKind) -> (CGEventField, CGEventField, CGEventField, IOHIDEventField) {
            axis == .vertical
                ? (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1, MMIOHIDEventFieldScrollY)
                : (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2, MMIOHIDEventFieldScrollX)
        }
        switch write {
        case let .continuous(value):
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: value ? 1 : 0)
        case let .lines(axis, value):
            event.setIntegerValueField(fields(axis).0, value: value)
        case let .fixed(axis, value):
            event.setDoubleValueField(fields(axis).1, value: value)
        case let .points(axis, value):
            event.setDoubleValueField(fields(axis).2, value: value)
        case let .hid(axis, value):
            if let hidEvent { IOHIDEventSetFloatValue(hidEvent, fields(axis).3, value) }
        }
    }

    private func senderID(of event: CGEvent) -> UInt64? {
        CGEventCopyIOHIDEvent(event).map { IOHIDEventGetSenderID($0) }
    }

    /// Marks the device as last used and asks for a device refresh when it is new.
    private func noteSender(_ sender: UInt64, markActive: Bool = true) {
        guard sender != 0 else { return }
        if registry.isKnown(sender) {
            if markActive { registry.markActive(sender) }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let report = lock.withLock {
            guard now - lastUnknownDeviceReport > 1 else { return false }
            lastUnknownDeviceReport = now
            return true
        }
        if report { DispatchQueue.main.async { [weak self] in self?.onUnknownDevice() } }
    }

    private func isBypassed(_ event: CGEvent) -> Bool {
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard pid > 0 else { return false }
        if let cached = lock.withLock({ bypassCache[pid] }) { return cached }
        let bypassed = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier.map(Self.bypassedSources.contains) ?? false
        lock.withLock { bypassCache[pid] = bypassed }
        return bypassed
    }
}
