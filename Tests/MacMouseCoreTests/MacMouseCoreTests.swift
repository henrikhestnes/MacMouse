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

final class ScrollRulesTests: XCTestCase {
    private let tickDown = ScrollAxis(lines: -1, fixed: -1, points: -10)
    private let tickRight = ScrollAxis(lines: 1, fixed: 1, points: 10)

    func testDefaultsReverseAndUseFourLines() {
        let decision = ScrollRules.decide(vertical: tickDown, horizontal: .zero, isContinuous: false,
                                          command: false, settings: MouseSettings())
        XCTAssertEqual(decision, .rewrite(vertical: .lines(4), horizontal: .lines(0)))
    }

    func testHorizontalUsesFiveLines() {
        let decision = ScrollRules.decide(vertical: .zero, horizontal: tickRight, isContinuous: false,
                                          command: false, settings: MouseSettings())
        XCTAssertEqual(decision, .rewrite(vertical: .lines(0), horizontal: .lines(-5)))
    }

    func testTrackpadScrollingIsLeftAlone() {
        let decision = ScrollRules.decide(vertical: tickDown, horizontal: .zero, isContinuous: true,
                                          command: true, settings: MouseSettings())
        XCTAssertEqual(decision, .pass)
    }

    func testReverseOnlyKeepsSystemAcceleration() {
        var settings = MouseSettings()
        settings.verticalLines = 0
        let fast = ScrollAxis(lines: -3, fixed: -2.5, points: -41)
        let decision = ScrollRules.decide(vertical: fast, horizontal: .zero, isContinuous: false,
                                          command: false, settings: settings)
        XCTAssertEqual(decision, .rewrite(vertical: .exact(ScrollAxis(lines: 3, fixed: 2.5, points: 41)), horizontal: .unchanged))
    }

    func testNothingToDo() {
        var settings = MouseSettings()
        (settings.reverseVertical, settings.verticalLines) = (false, 0)
        XCTAssertEqual(ScrollRules.decide(vertical: tickDown, horizontal: .zero, isContinuous: false,
                                          command: false, settings: settings), .pass)
    }

    func testCommandScrollZoomsAfterReversing() {
        // A tick toward the user is -1; reversed it is +1, which zooms in.
        XCTAssertEqual(ScrollRules.decide(vertical: tickDown, horizontal: .zero, isContinuous: false,
                                          command: true, settings: MouseSettings()), .zoom(zoomIn: true))
        var settings = MouseSettings()
        settings.commandScrollZooms = false
        XCTAssertEqual(ScrollRules.decide(vertical: tickDown, horizontal: .zero, isContinuous: false,
                                          command: true, settings: settings),
                       .rewrite(vertical: .lines(4), horizontal: .lines(0)))
    }

    func testCommandWithHorizontalScrollDoesNotZoom() {
        XCTAssertEqual(ScrollRules.decide(vertical: .zero, horizontal: tickRight, isContinuous: false,
                                          command: true, settings: MouseSettings()),
                       .rewrite(vertical: .lines(0), horizontal: .lines(-5)))
    }

    func testThrottle() {
        var throttle = ActionThrottle(interval: 0.3)
        XCTAssertTrue(throttle.allows(at: 10))
        XCTAssertFalse(throttle.allows(at: 10.2))
        XCTAssertTrue(throttle.allows(at: 10.31))
    }
}

final class ButtonRulesTests: XCTestCase {
    func testDefaultsPassBackAndForwardThrough() {
        let settings = MouseSettings()
        XCTAssertEqual(ButtonRules.decide(button: 2, phase: .down, settings: settings), .pass)
        XCTAssertEqual(ButtonRules.decide(button: 3, phase: .down, settings: settings), .pass)
        XCTAssertEqual(ButtonRules.decide(button: 4, phase: .up, settings: settings), .pass)
        XCTAssertEqual(ButtonRules.decide(button: 9, phase: .down, settings: settings), .pass)
    }

    func testSixthButtonOpensMissionControlOnce() {
        let settings = MouseSettings()
        XCTAssertEqual(ButtonRules.decide(button: 5, phase: .down, settings: settings), .perform(.missionControl))
        XCTAssertEqual(ButtonRules.decide(button: 5, phase: .dragged, settings: settings), .swallow)
        XCTAssertEqual(ButtonRules.decide(button: 5, phase: .up, settings: settings), .swallow)
    }

    func testRemapsAndDisables() {
        var settings = MouseSettings()
        settings.backButton = .forward
        settings.forwardButton = .disabled
        settings.middleButton = .back
        XCTAssertEqual(ButtonRules.decide(button: 3, phase: .dragged, settings: settings), .remap(to: 4))
        XCTAssertEqual(ButtonRules.decide(button: 4, phase: .down, settings: settings), .swallow)
        XCTAssertEqual(ButtonRules.decide(button: 2, phase: .up, settings: settings), .remap(to: 3))
    }
}
