/// System features a button can trigger.
public enum SystemAction: Equatable, Sendable {
    case missionControl, appExpose, showDesktop
}

public enum ButtonPhase: Sendable { case down, dragged, up }

public enum ButtonDecision: Equatable, Sendable {
    case pass
    /// Rewrite the event as this Quartz button number.
    case remap(to: Int64)
    case swallow
    /// Swallow the event and trigger this.
    case perform(SystemAction)
}

/// LinearMouse's button mappings as its legacy `{button, action}` entries behave:
///
/// - A mapping matches only when no modifier key (⌘ ⇧ ⌥ ⌃) is held at the press, because the
///   mapping's command/shift/option/control are all false.
/// - Mouse-button actions (back, forward, middle) remap the press, its drags and its release.
/// - Other actions are short-press actions: the press and drags are swallowed and the action
///   runs when the button is released.
/// - A captured press keeps its mapping until release, whatever the modifiers or device.
public struct ButtonMapper: Sendable {
    private var captured: [Int64: ButtonAction] = [:]

    public init() {}

    /// - Parameter matchesDevice: whether the event comes from a mouse the settings apply to.
    public mutating func process(button: Int64, phase: ButtonPhase, modifiersHeld: Bool,
                                 matchesDevice: Bool, settings: MouseSettings) -> ButtonDecision {
        switch phase {
        case .down:
            if let action = captured[button] {
                // A repeated press of a captured button stays captured.
                return Self.decision(for: action, button: button, phase: .dragged)
            }
            let action = settings.action(forButton: button)
            guard matchesDevice, !modifiersHeld, action != .standard else { return .pass }
            captured[button] = action
            return Self.decision(for: action, button: button, phase: .down)
        case .dragged:
            guard let action = captured[button] else { return .pass }
            return Self.decision(for: action, button: button, phase: .dragged)
        case .up:
            guard let action = captured.removeValue(forKey: button) else { return .pass }
            return Self.decision(for: action, button: button, phase: .up)
        }
    }

    private static func decision(for action: ButtonAction, button: Int64, phase: ButtonPhase) -> ButtonDecision {
        let remapTarget: Int64? = switch action {
        case .back: 3
        case .forward: 4
        case .middleClick: 2
        default: nil
        }
        if let remapTarget { return remapTarget == button ? .pass : .remap(to: remapTarget) }
        let system: SystemAction? = switch action {
        case .missionControl: .missionControl
        case .appExpose: .appExpose
        case .showDesktop: .showDesktop
        default: nil
        }
        if let system, phase == .up { return .perform(system) }
        return .swallow
    }
}
