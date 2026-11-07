/// Which mice the settings apply to, like a LinearMouse scheme's `if.device` condition
/// (category mouse). A nil field matches anything, so `DeviceMatch()` matches every mouse.
public struct DeviceMatch: Codable, Equatable, Hashable, Sendable {
    public var vendorID: Int?
    public var productID: Int?
    public var productName: String?

    public init(vendorID: Int? = nil, productID: Int? = nil, productName: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.productName = productName
    }

    public static let allMice = DeviceMatch()
    /// The Logitech receiver the LinearMouse configuration targets.
    public static let logitechUSBReceiver = DeviceMatch(vendorID: 0x46D, productID: 0xC548, productName: "USB Receiver")

    public var isAllMice: Bool { vendorID == nil && productID == nil && productName == nil }

    public func matches(vendorID: Int?, productID: Int?, productName: String?) -> Bool {
        (self.vendorID == nil || self.vendorID == vendorID)
            && (self.productID == nil || self.productID == productID)
            && (self.productName == nil || self.productName == productName)
    }

    public var title: String {
        if isAllMice { return "All mice" }
        let ids = [vendorID, productID].map { $0.map { String(format: "%04x", $0) } ?? "*" }.joined(separator: ":")
        return "\(productName ?? "Any mouse") (\(ids))"
    }
}
