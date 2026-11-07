/// Converts LinearMouse's pointer settings to the HID properties macOS reads.
public enum PointerMath {
    /// 1 / HIDPointerResolution spans this range as the speed goes from 0 to 1.
    private static let inverseResolutionRange = (1.0 / 1200)...(1.0 / 40)

    /// The HIDPointerResolution (counts per inch) for a speed in 0...1. Lower is faster.
    public static func resolution(forSpeed speed: Double) -> Double {
        let clamped = min(max(speed, 0), 1)
        let inverse = inverseResolutionRange.lowerBound
            + clamped * (inverseResolutionRange.upperBound - inverseResolutionRange.lowerBound)
        return min(max(1 / inverse, 10), 1995)
    }

    /// The IOFixed (16.16) encoding HID properties use.
    public static func fixed(_ value: Double) -> Int32 {
        Int32((value * 65_536).rounded())
    }

    public static func double(fromFixed value: Int32) -> Double {
        Double(value) / 65_536
    }
}

/// Which devices get the pointer settings.
public enum DeviceKind: Equatable, Sendable {
    case mouse
    case trackpad

    private static let appleVendorIDs: Set<Int> = [0x004C, 0x05AC]
    private static let magicMouseProductIDs: Set<Int> = [0x0269, 0x030D]

    /// A pointing service is a trackpad when it is a touchpad digitizer, except the Magic Mouse,
    /// which reports itself as one.
    public static func classify(vendorID: Int?, productID: Int?, isTouchpad: Bool) -> DeviceKind {
        if let vendorID, let productID, appleVendorIDs.contains(vendorID), magicMouseProductIDs.contains(productID) {
            return .mouse
        }
        return isTouchpad ? .trackpad : .mouse
    }
}
