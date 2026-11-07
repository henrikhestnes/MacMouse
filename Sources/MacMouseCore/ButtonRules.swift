/// System features a button can trigger.
public enum SystemAction: Equatable, Sendable {
    case missionControl, appExpose, showDesktop
}

public enum ButtonPhase: Sendable { case down, dragged, up }

public enum ButtonDecision: Equatable, Sendable {
    case pass
    /// Rewrite the event as this Quartz button number, keeping presses and drags intact.
    case remap(to: Int64)
    case swallow
    /// Swallow the press and trigger this.
    case perform(SystemAction)
}

public enum ButtonRules {
    public static func decide(button: Int64, phase: ButtonPhase, settings: MouseSettings) -> ButtonDecision {
        let remapTarget: Int64?
        let system: SystemAction?
        switch settings.action(forButton: button) {
        case .standard: return .pass
        case .disabled: return .swallow
        case .back: (remapTarget, system) = (3, nil)
        case .forward: (remapTarget, system) = (4, nil)
        case .middleClick: (remapTarget, system) = (2, nil)
        case .missionControl: (remapTarget, system) = (nil, .missionControl)
        case .appExpose: (remapTarget, system) = (nil, .appExpose)
        case .showDesktop: (remapTarget, system) = (nil, .showDesktop)
        }
        if let remapTarget { return remapTarget == button ? .pass : .remap(to: remapTarget) }
        guard let system else { return .pass }
        return phase == .down ? .perform(system) : .swallow
    }
}
