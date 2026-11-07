import Foundation

/// What a mouse button does.
public enum ButtonAction: String, Codable, CaseIterable, Sendable {
    /// Leave the button alone.
    case standard
    case back
    case forward
    case middleClick
    case missionControl
    case appExpose
    case showDesktop
    /// Swallow the button.
    case disabled

    public var title: String {
        switch self {
        case .standard: "Default"
        case .back: "Back"
        case .forward: "Forward"
        case .middleClick: "Middle Click"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .disabled: "Do Nothing"
        }
    }
}

/// Every setting. The defaults reproduce the LinearMouse configuration this app replaces: for the
/// Logitech USB Receiver only, pointer speed 0.1 with acceleration 5, reversed scrolling by 4 lines
/// vertically and 5 horizontally, ⌘-scroll to zoom, and the sixth button opening Mission Control.
public struct MouseSettings: Codable, Equatable, Sendable {
    /// The mice everything below applies to. Other mice and all trackpads are left alone.
    public var device = DeviceMatch.logitechUSBReceiver

    // Pointer.
    /// 0 is slowest, 1 fastest. LinearMouse's scale.
    public var pointerSpeed = 0.1
    /// 0...20, LinearMouse's scale. macOS's own default is about 0.69.
    public var pointerAcceleration = 5.0
    public var disablePointerAcceleration = false

    // Scrolling.
    public var reverseVertical = true
    public var reverseHorizontal = true
    /// Lines per wheel tick; 0 leaves the system's accelerated scrolling alone.
    public var verticalLines = 4
    public var horizontalLines = 5
    public var commandScrollZooms = true

    // Buttons, by Quartz button number: 2 middle, 3 back, 4 forward, 5 the sixth button.
    public var middleButton = ButtonAction.standard
    public var backButton = ButtonAction.back
    public var forwardButton = ButtonAction.forward
    public var sixthButton = ButtonAction.missionControl

    public init() {}

    public static let pointerAccelerationRange = 0.0...20.0
    public static let linesRange = 0...20
    /// The Quartz numbers of the buttons that can be remapped.
    public static let mappableButtons: [Int64] = [2, 3, 4, 5]

    public func action(forButton number: Int64) -> ButtonAction {
        switch number {
        case 2: middleButton
        case 3: backButton
        case 4: forwardButton
        case 5: sixthButton
        default: .standard
        }
    }

    public mutating func setAction(_ action: ButtonAction, forButton number: Int64) {
        switch number {
        case 2: middleButton = action
        case 3: backButton = action
        case 4: forwardButton = action
        case 5: sixthButton = action
        default: break
        }
    }

    /// Missing or unreadable values fall back to the defaults, so settings saved by an older
    /// version keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let defaults = MouseSettings()
        device = value(.device, defaults.device)
        pointerSpeed = min(max(value(.pointerSpeed, defaults.pointerSpeed), 0), 1)
        pointerAcceleration = min(max(value(.pointerAcceleration, defaults.pointerAcceleration), 0), 20)
        disablePointerAcceleration = value(.disablePointerAcceleration, defaults.disablePointerAcceleration)
        reverseVertical = value(.reverseVertical, defaults.reverseVertical)
        reverseHorizontal = value(.reverseHorizontal, defaults.reverseHorizontal)
        verticalLines = min(max(value(.verticalLines, defaults.verticalLines), 0), 20)
        horizontalLines = min(max(value(.horizontalLines, defaults.horizontalLines), 0), 20)
        commandScrollZooms = value(.commandScrollZooms, defaults.commandScrollZooms)
        middleButton = value(.middleButton, defaults.middleButton)
        backButton = value(.backButton, defaults.backButton)
        forwardButton = value(.forwardButton, defaults.forwardButton)
        sixthButton = value(.sixthButton, defaults.sixthButton)
    }
}
