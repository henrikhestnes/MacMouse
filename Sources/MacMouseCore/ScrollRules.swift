/// One axis of a scroll wheel event: whole lines, the fixed-point line delta, and pixels.
public struct ScrollAxis: Equatable, Sendable {
    public var lines: Int64
    public var fixed: Double
    public var points: Double

    public init(lines: Int64, fixed: Double, points: Double) {
        self.lines = lines
        self.fixed = fixed
        self.points = points
    }

    public static let zero = ScrollAxis(lines: 0, fixed: 0, points: 0)

    var negated: ScrollAxis { ScrollAxis(lines: -lines, fixed: -fixed, points: -points) }
}

/// How to change one axis of the event.
public enum AxisWrite: Equatable, Sendable {
    case unchanged
    /// Set the line delta only. Quartz then recomputes the fixed-point and pixel deltas the way
    /// it does for a real wheel tick.
    case lines(Int64)
    /// Set all three deltas, lines first so Quartz's recomputation is overwritten.
    case exact(ScrollAxis)
}

public enum ScrollDecision: Equatable, Sendable {
    case pass
    case rewrite(vertical: AxisWrite, horizontal: AxisWrite)
    /// Swallow the event and zoom in or out with ⌘+ or ⌘−.
    case zoom(zoomIn: Bool)
}

/// Mirrors LinearMouse's scroll pipeline for wheel mice: reverse, then fixed line distance per
/// tick (horizontal before vertical), then ⌘-scroll zoom.
public enum ScrollRules {
    /// - Parameter isContinuous: true for trackpads and Magic Mouse, which are left alone.
    public static func decide(vertical: ScrollAxis, horizontal: ScrollAxis, isContinuous: Bool,
                              command: Bool, settings: MouseSettings) -> ScrollDecision {
        guard !isContinuous else { return .pass }
        var vertical = vertical, horizontal = horizontal
        var verticalWrite = AxisWrite.unchanged, horizontalWrite = AxisWrite.unchanged

        if settings.reverseVertical, vertical != .zero {
            vertical = vertical.negated
            verticalWrite = .exact(vertical)
        }
        if settings.reverseHorizontal, horizontal != .zero {
            horizontal = horizontal.negated
            horizontalWrite = .exact(horizontal)
        }
        if settings.horizontalLines > 0, horizontal.lines != 0 {
            horizontal.lines = horizontal.lines.signum() * Int64(settings.horizontalLines)
            horizontalWrite = .lines(horizontal.lines)
            vertical.lines = 0
            verticalWrite = .lines(0)
        }
        if settings.verticalLines > 0, vertical.lines != 0 {
            vertical.lines = vertical.lines.signum() * Int64(settings.verticalLines)
            verticalWrite = .lines(vertical.lines)
            horizontal.lines = 0
            horizontalWrite = .lines(0)
        }
        if settings.commandScrollZooms, command, vertical.lines != 0 {
            return .zoom(zoomIn: vertical.lines > 0)
        }
        if verticalWrite == .unchanged, horizontalWrite == .unchanged { return .pass }
        return .rewrite(vertical: verticalWrite, horizontal: horizontalWrite)
    }
}

/// Lets an action run at most once per interval, so a fast wheel spin zooms a few steps
/// instead of dozens.
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
