import CoreGraphics
import Foundation
import MacMouseCore

/// Rewrites scroll wheel and extra-button events. Needs Accessibility access.
final class EventInterceptor {
    var settings: () -> MouseSettings = { MouseSettings() }
    var isActive: () -> Bool = { false }

    private var tap: CFMachPort?
    private var zoomThrottle = ActionThrottle()

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = [CGEventType.scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
            .reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            Unmanaged<EventInterceptor>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case _ where !isActive():
            return pass
        case .scrollWheel:
            return handleScroll(event) ? pass : nil
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return handleButton(type, event) ? pass : nil
        default:
            return pass
        }
    }

    /// Returns false to swallow the event.
    private func handleScroll(_ event: CGEvent) -> Bool {
        let decision = ScrollRules.decide(
            vertical: axis(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1),
            horizontal: axis(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            command: event.flags.contains(.maskCommand),
            settings: settings())
        switch decision {
        case .pass:
            return true
        case let .rewrite(vertical, horizontal):
            write(vertical, to: event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
            write(horizontal, to: event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
            return true
        case let .zoom(zoomIn):
            if zoomThrottle.allows(at: ProcessInfo.processInfo.systemUptime) { SystemActions.zoom(in: zoomIn) }
            return false
        }
    }

    private func axis(_ event: CGEvent, _ lines: CGEventField, _ fixed: CGEventField, _ points: CGEventField) -> ScrollAxis {
        ScrollAxis(lines: event.getIntegerValueField(lines), fixed: event.getDoubleValueField(fixed),
                   points: event.getDoubleValueField(points))
    }

    private func write(_ write: AxisWrite, to event: CGEvent, _ lines: CGEventField, _ fixed: CGEventField, _ points: CGEventField) {
        switch write {
        case .unchanged:
            break
        case let .lines(value):
            // Quartz recomputes the fixed-point and pixel deltas from the line delta.
            event.setIntegerValueField(lines, value: value)
        case let .exact(axis):
            event.setIntegerValueField(lines, value: axis.lines)
            event.setDoubleValueField(fixed, value: axis.fixed)
            event.setDoubleValueField(points, value: axis.points)
        }
    }

    /// Returns false to swallow the event.
    private func handleButton(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let phase: ButtonPhase = type == .otherMouseDown ? .down : type == .otherMouseUp ? .up : .dragged
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        switch ButtonRules.decide(button: button, phase: phase, settings: settings()) {
        case .pass:
            return true
        case let .remap(number):
            event.setIntegerValueField(.mouseEventButtonNumber, value: number)
            return true
        case .swallow:
            return false
        case let .perform(action):
            SystemActions.perform(action)
            return false
        }
    }
}
