public enum ScrollAxisKind: Sendable { case vertical, horizontal }

/// One axis of a scroll wheel event as Quartz reports it.
public struct ScrollAxis: Equatable, Sendable {
    public var lines: Int64
    public var fixed: Double
    public var points: Double
    /// The scroll value of the IOHIDEvent behind the event.
    public var hid: Double

    public init(lines: Int64, fixed: Double, points: Double, hid: Double = 0) {
        self.lines = lines
        self.fixed = fixed
        self.points = points
        self.hid = hid
    }

    public static let zero = ScrollAxis(lines: 0, fixed: 0, points: 0)
}

public struct ScrollEvent: Equatable, Sendable {
    public var vertical: ScrollAxis
    public var horizontal: ScrollAxis
    public var isContinuous: Bool
    public var scrollPhaseBegan: Bool
    public var isMomentum: Bool
    public var momentumEnded: Bool
    public var command: Bool

    public init(vertical: ScrollAxis, horizontal: ScrollAxis = .zero, isContinuous: Bool = false,
                scrollPhaseBegan: Bool = false, isMomentum: Bool = false, momentumEnded: Bool = false,
                command: Bool = false) {
        self.vertical = vertical
        self.horizontal = horizontal
        self.isContinuous = isContinuous
        self.scrollPhaseBegan = scrollPhaseBegan
        self.isMomentum = isMomentum
        self.momentumEnded = momentumEnded
        self.command = command
    }
}

/// A field write, applied to the event in order. Setting a line delta makes Quartz recompute
/// that axis's fixed-point and pixel deltas, exactly as when LinearMouse sets it.
public enum ScrollWrite: Equatable, Sendable {
    case continuous(Bool)
    case lines(ScrollAxisKind, Int64)
    case fixed(ScrollAxisKind, Double)
    case points(ScrollAxisKind, Double)
    case hid(ScrollAxisKind, Double)
}

public enum ScrollDecision: Equatable, Sendable {
    case pass
    case rewrite([ScrollWrite])
    case swallow
    /// Swallow the event and zoom with ⌘+ or ⌘− (subject to the zoom throttle).
    case zoom(zoomIn: Bool)
}

/// LinearMouse's scroll pipeline for a matching mouse, in its order:
/// ScrollGestureTransformer → ReverseScrollingTransformer → LinearScrollingHorizontalTransformer
/// → LinearScrollingVerticalTransformer → ModifierActionsTransformer (⌘ zoom).
/// Scroll acceleration 1 and speed 0, the LinearMouse defaults, are no-ops and so not modelled.
public struct ScrollProcessor: Sendable {
    /// Set when a zoom consumes a gesture, so its momentum tail is discarded too.
    private var gestureOwned = false

    public init() {}

    public mutating func process(_ event: ScrollEvent, settings: MouseSettings) -> ScrollDecision {
        // ScrollGestureTransformer.
        if event.isMomentum {
            if gestureOwned {
                if event.momentumEnded { gestureOwned = false }
                return .swallow
            }
        } else if event.scrollPhaseBegan || Self.hasDelta(event) {
            gestureOwned = false
        }

        var state = event
        var writes: [ScrollWrite] = []

        // ReverseScrollingTransformer negates every field of each reversed axis.
        if settings.reverseVertical || settings.reverseHorizontal {
            for (axis, reversed) in [(ScrollAxisKind.horizontal, settings.reverseHorizontal), (.vertical, settings.reverseVertical)] where reversed {
                var value = axis == .vertical ? state.vertical : state.horizontal
                value = ScrollAxis(lines: -value.lines, fixed: -value.fixed, points: -value.points, hid: -value.hid)
                writes += [.lines(axis, value.lines), .fixed(axis, value.fixed), .points(axis, value.points), .hid(axis, value.hid)]
                if axis == .vertical { state.vertical = value } else { state.horizontal = value }
            }
        }

        // LinearScrollingHorizontalTransformer, then LinearScrollingVerticalTransformer.
        for axis in [ScrollAxisKind.horizontal, .vertical] {
            let lines = axis == .vertical ? settings.verticalLines : settings.horizontalLines
            let sign = Self.signum(axis == .vertical ? state.vertical : state.horizontal, continuous: state.isContinuous)
            guard lines > 0, sign != 0 else { continue }
            guard !state.isMomentum else { return .swallow }
            let other: ScrollAxisKind = axis == .vertical ? .horizontal : .vertical
            let value = sign * Int64(lines)
            writes += [.continuous(false), .lines(axis, value), .lines(other, 0)]
            state.isContinuous = false
            if axis == .vertical {
                state.vertical.lines = value
                state.horizontal.lines = 0
            } else {
                state.horizontal.lines = value
                state.vertical.lines = 0
            }
        }

        // ModifierActionsTransformer: vertical scrolling with ⌘ zooms.
        let verticalSign = Self.signum(state.vertical, continuous: state.isContinuous)
        if settings.commandScrollZooms, state.command, verticalSign != 0 {
            guard !state.isMomentum else { return .swallow }
            gestureOwned = true
            return .zoom(zoomIn: verticalSign > 0)
        }

        return writes.isEmpty ? .pass : .rewrite(writes)
    }

    /// LinearMouse's deltaYSignum/deltaXSignum.
    static func signum(_ axis: ScrollAxis, continuous: Bool) -> Int64 {
        continuous ? (axis.points > 0 ? 1 : axis.points < 0 ? -1 : 0) : axis.lines.signum()
    }

    /// LinearMouse's ScrollInput.read(...) != nil.
    static func hasDelta(_ event: ScrollEvent) -> Bool {
        func delta(_ axis: ScrollAxis) -> Double {
            if event.isContinuous { return axis.points }
            if axis.fixed != 0 { return axis.fixed }
            if axis.lines != 0 { return Double(axis.lines) }
            return axis.points / 10
        }
        let x = delta(event.horizontal), y = delta(event.vertical)
        return x.isFinite && y.isFinite && (x != 0 || y != 0)
    }
}

/// Lets an action run at most once per interval, like LinearMouse's ScrollActionThrottle.
public struct ActionThrottle: Sendable {
    public let interval: Double
    private var last: Double?

    public init(interval: Double = 0.3) { self.interval = interval }

    public mutating func allows(at time: Double) -> Bool {
        if let last, time >= last, time - last < interval { return false }
        last = time
        return true
    }
}
