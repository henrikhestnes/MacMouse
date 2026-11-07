import Foundation
import XCTest
@testable import MacMouseCore

final class SettingsTests: XCTestCase {
    func testDefaultsMatchTheLinearMouseConfiguration() {
        let settings = MouseSettings()
        XCTAssertEqual(settings.pointerSpeed, 0.1)
        XCTAssertEqual(settings.pointerAcceleration, 5)
        XCTAssertFalse(settings.disablePointerAcceleration)
        XCTAssertTrue(settings.reverseVertical)
        XCTAssertTrue(settings.reverseHorizontal)
        XCTAssertEqual(settings.verticalLines, 4)
        XCTAssertEqual(settings.horizontalLines, 5)
        XCTAssertTrue(settings.commandScrollZooms)
        XCTAssertEqual(settings.action(forButton: 2), .standard)
        XCTAssertEqual(settings.action(forButton: 3), .back)
        XCTAssertEqual(settings.action(forButton: 4), .forward)
        XCTAssertEqual(settings.action(forButton: 5), .missionControl)
    }

    func testRoundTripsAndFillsMissingValues() throws {
        var settings = MouseSettings()
        settings.verticalLines = 7
        settings.sixthButton = .appExpose
        let decoded = try JSONDecoder().decode(MouseSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)

        let partial = try JSONDecoder().decode(MouseSettings.self, from: Data(#"{"verticalLines": 99, "middleButton": "bogus"}"#.utf8))
        XCTAssertEqual(partial.verticalLines, 20)
        XCTAssertEqual(partial.middleButton, .standard)
        XCTAssertEqual(partial.pointerSpeed, 0.1)
    }

    func testSetActionUpdatesTheMatchingButton() {
        var settings = MouseSettings()
        settings.setAction(.showDesktop, forButton: 2)
        XCTAssertEqual(settings.middleButton, .showDesktop)
        XCTAssertEqual(settings.action(forButton: 7), .standard)
    }
}

final class PointerMathTests: XCTestCase {
    func testResolutionMatchesLinearMouse() {
        XCTAssertEqual(PointerMath.resolution(forSpeed: 0), 1200, accuracy: 0.001)
        XCTAssertEqual(PointerMath.resolution(forSpeed: 1), 40, accuracy: 0.001)
        XCTAssertEqual(PointerMath.resolution(forSpeed: 0.1), 307.692, accuracy: 0.001)
        XCTAssertEqual(PointerMath.resolution(forSpeed: 5), 40, accuracy: 0.001)
    }

    func testFixedPoint() {
        XCTAssertEqual(PointerMath.fixed(5), 327_680)
        XCTAssertEqual(PointerMath.fixed(-1), -65_536)
        XCTAssertEqual(PointerMath.double(fromFixed: 45_056), 0.6875)
    }

    func testDeviceKinds() {
        XCTAssertEqual(DeviceKind.classify(vendorID: 0x46D, productID: 0xC548, isTouchpad: false), .mouse)
        XCTAssertEqual(DeviceKind.classify(vendorID: 0, productID: 0, isTouchpad: true), .trackpad)
        XCTAssertEqual(DeviceKind.classify(vendorID: 0x5AC, productID: 0x030D, isTouchpad: true), .mouse)
        XCTAssertEqual(DeviceKind.classify(vendorID: nil, productID: nil, isTouchpad: false), .mouse)
    }
}

final class DeviceMatchTests: XCTestCase {
    func testDefaultTargetsTheLogitechReceiverOnly() {
        let match = MouseSettings().device
        XCTAssertEqual(match, .logitechUSBReceiver)
        XCTAssertTrue(match.matches(vendorID: 0x46D, productID: 0xC548, productName: "USB Receiver"))
        XCTAssertFalse(match.matches(vendorID: 0x46D, productID: 0xC548, productName: "MX Master 3S"))
        XCTAssertFalse(match.matches(vendorID: 0x5AC, productID: 0x030D, productName: "Magic Mouse"))
        XCTAssertTrue(DeviceMatch.allMice.matches(vendorID: 1, productID: 2, productName: nil))
    }

    func testAllMiceSurvivesSaving() throws {
        var settings = MouseSettings()
        settings.device = .allMice
        let decoded = try JSONDecoder().decode(MouseSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.device, .allMice)
    }
}

final class ScrollProcessorTests: XCTestCase {
    private let tickDown = ScrollAxis(lines: -1, fixed: -1, points: -10, hid: -1)
    private let tickRight = ScrollAxis(lines: 1, fixed: 1, points: 10, hid: 1)

    private func process(_ event: ScrollEvent, _ settings: MouseSettings = MouseSettings()) -> ScrollDecision {
        var processor = ScrollProcessor()
        return processor.process(event, settings: settings)
    }

    func testVerticalTickIsReversedThenSetToFourLines() {
        XCTAssertEqual(process(ScrollEvent(vertical: tickDown)), .rewrite([
            .lines(.horizontal, 0), .fixed(.horizontal, 0), .points(.horizontal, 0), .hid(.horizontal, 0),
            .lines(.vertical, 1), .fixed(.vertical, 1), .points(.vertical, 10), .hid(.vertical, 1),
            .continuous(false), .lines(.vertical, 4), .lines(.horizontal, 0)
        ]))
    }

    func testHorizontalTickIsReversedThenSetToFiveLines() {
        XCTAssertEqual(process(ScrollEvent(vertical: .zero, horizontal: tickRight)), .rewrite([
            .lines(.horizontal, -1), .fixed(.horizontal, -1), .points(.horizontal, -10), .hid(.horizontal, -1),
            .lines(.vertical, 0), .fixed(.vertical, 0), .points(.vertical, 0), .hid(.vertical, 0),
            .continuous(false), .lines(.horizontal, -5), .lines(.vertical, 0)
        ]))
    }

    func testContinuousEventsFromTheMouseBecomeLineScrolls() {
        let decision = process(ScrollEvent(vertical: ScrollAxis(lines: 0, fixed: 0.3, points: 3), isContinuous: true))
        guard case let .rewrite(writes) = decision else { return XCTFail("\(decision)") }
        XCTAssertEqual(Array(writes.suffix(3)), [.continuous(false), .lines(.vertical, -4), .lines(.horizontal, 0)])
    }

    func testMomentumWithDeltaIsSwallowed() {
        XCTAssertEqual(process(ScrollEvent(vertical: tickDown, isMomentum: true)), .swallow)
    }

    func testReverseOnlyKeepsSystemAcceleration() {
        var settings = MouseSettings()
        (settings.verticalLines, settings.reverseHorizontal) = (0, false)
        let fast = ScrollAxis(lines: -3, fixed: -2.5, points: -41, hid: -3)
        XCTAssertEqual(process(ScrollEvent(vertical: fast), settings),
                       .rewrite([.lines(.vertical, 3), .fixed(.vertical, 2.5), .points(.vertical, 41), .hid(.vertical, 3)]))
    }

    func testNothingToDo() {
        var settings = MouseSettings()
        (settings.reverseVertical, settings.reverseHorizontal, settings.verticalLines) = (false, false, 0)
        XCTAssertEqual(process(ScrollEvent(vertical: tickDown), settings), .pass)
    }

    func testCommandScrollZoomsAfterReversing() {
        // A tick toward the user is -1; reversed it is +1, which zooms in.
        XCTAssertEqual(process(ScrollEvent(vertical: tickDown, command: true)), .zoom(zoomIn: true))
        var settings = MouseSettings()
        settings.commandScrollZooms = false
        guard case .rewrite = process(ScrollEvent(vertical: tickDown, command: true), settings) else { return XCTFail() }
    }

    func testCommandWithHorizontalScrollDoesNotZoom() {
        guard case .rewrite = process(ScrollEvent(vertical: .zero, horizontal: tickRight, command: true)) else { return XCTFail() }
    }

    func testZoomDiscardsTheGesturesMomentum() {
        var processor = ScrollProcessor()
        let settings = MouseSettings()
        let continuous = ScrollAxis(lines: 0, fixed: 0, points: 4)
        XCTAssertEqual(processor.process(ScrollEvent(vertical: continuous, isContinuous: true, command: true), settings: settings),
                       .zoom(zoomIn: false))
        XCTAssertEqual(processor.process(ScrollEvent(vertical: .zero, isContinuous: true, isMomentum: true), settings: settings), .swallow)
        XCTAssertEqual(processor.process(ScrollEvent(vertical: .zero, isContinuous: true, isMomentum: true, momentumEnded: true),
                                         settings: settings), .swallow)
        XCTAssertEqual(processor.process(ScrollEvent(vertical: .zero, isContinuous: true, isMomentum: true), settings: settings), .rewrite([
            .lines(.horizontal, 0), .fixed(.horizontal, 0), .points(.horizontal, 0), .hid(.horizontal, 0),
            .lines(.vertical, 0), .fixed(.vertical, 0), .points(.vertical, 0), .hid(.vertical, 0)
        ]))
    }

    func testThrottle() {
        var throttle = ActionThrottle(interval: 0.3)
        XCTAssertTrue(throttle.allows(at: 10))
        XCTAssertFalse(throttle.allows(at: 10.2))
        XCTAssertTrue(throttle.allows(at: 10.31))
    }
}

final class ButtonMapperTests: XCTestCase {
    private let settings = MouseSettings()

    func testBackAndForwardPassThrough() {
        var mapper = ButtonMapper()
        for button: Int64 in [3, 4] {
            for phase in [ButtonPhase.down, .dragged, .up] {
                XCTAssertEqual(mapper.process(button: button, phase: phase, modifiersHeld: false, matchesDevice: true, settings: settings), .pass)
            }
        }
    }

    func testSixthButtonOpensMissionControlOnRelease() {
        var mapper = ButtonMapper()
        XCTAssertEqual(mapper.process(button: 5, phase: .down, modifiersHeld: false, matchesDevice: true, settings: settings), .swallow)
        XCTAssertEqual(mapper.process(button: 5, phase: .dragged, modifiersHeld: false, matchesDevice: true, settings: settings), .swallow)
        // The release belongs to the captured press, even with a modifier now held.
        XCTAssertEqual(mapper.process(button: 5, phase: .up, modifiersHeld: true, matchesDevice: true, settings: settings),
                       .perform(.missionControl))
    }

    func testModifierHeldAtPressSkipsTheMapping() {
        var mapper = ButtonMapper()
        XCTAssertEqual(mapper.process(button: 5, phase: .down, modifiersHeld: true, matchesDevice: true, settings: settings), .pass)
        XCTAssertEqual(mapper.process(button: 5, phase: .up, modifiersHeld: false, matchesDevice: true, settings: settings), .pass)
    }

    func testOtherDevicesAreLeftAlone() {
        var mapper = ButtonMapper()
        XCTAssertEqual(mapper.process(button: 5, phase: .down, modifiersHeld: false, matchesDevice: false, settings: settings), .pass)
        XCTAssertEqual(mapper.process(button: 5, phase: .up, modifiersHeld: false, matchesDevice: false, settings: settings), .pass)
    }

    func testRemapsWholeClickAndDisables() {
        var settings = MouseSettings()
        settings.middleButton = .back
        settings.forwardButton = .disabled
        var mapper = ButtonMapper()
        for phase in [ButtonPhase.down, .dragged, .up] {
            XCTAssertEqual(mapper.process(button: 2, phase: phase, modifiersHeld: false, matchesDevice: true, settings: settings), .remap(to: 3))
            XCTAssertEqual(mapper.process(button: 4, phase: phase, modifiersHeld: false, matchesDevice: true, settings: settings), .swallow)
        }
    }
}
