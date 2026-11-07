import CPrivate
import Foundation
import IOKit.hid
import MacMouseCore

/// Sets pointer speed and acceleration on every connected mouse (never trackpads) through the
/// HID event system, the way LinearMouse does. Needs no permission.
final class PointerController {
    private static let resolutionKey = "HIDPointerResolution"
    private static let linearScalingKey = "HIDUseLinearScalingMouseAcceleration"

    private let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
    /// Each mouse's values before this app changed them, keyed by registry ID.
    private var originals: [String: [String: CFTypeRef]] = [:]

    /// Names of the connected mice, from the last `apply`.
    private(set) var mouseNames: [String] = []

    /// Writes only values that differ, so it is cheap to call repeatedly to undo changes made
    /// by System Settings or a reconnecting device.
    func apply(_ settings: MouseSettings) {
        let mice = self.mice()
        mouseNames = Array(Set(mice.compactMap { property($0, "Product") as? String })).sorted()
        for service in mice {
            let accelerationKey = accelerationKey(of: service)
            let keys = [Self.resolutionKey, accelerationKey, Self.linearScalingKey]
            let id = registryID(of: service)
            if originals[id] == nil {
                originals[id] = Dictionary(uniqueKeysWithValues: keys.compactMap { key in property(service, key).map { (key, $0) } })
            }
            let supportsLinearScaling = originals[id]?[Self.linearScalingKey] != nil

            if settings.disablePointerAcceleration {
                if supportsLinearScaling {
                    setIfChanged(service, Self.linearScalingKey, 1)
                } else {
                    setIfChanged(service, accelerationKey, Int(PointerMath.fixed(-1)))
                }
                continue
            }
            if supportsLinearScaling { setIfChanged(service, Self.linearScalingKey, 0) }
            let resolutionChanged = setIfChanged(service, Self.resolutionKey,
                                                 Int(PointerMath.fixed(PointerMath.resolution(forSpeed: settings.pointerSpeed))))
            let acceleration = Int(PointerMath.fixed(settings.pointerAcceleration))
            // A new resolution takes effect only once acceleration is written again.
            if resolutionChanged {
                set(service, accelerationKey, acceleration)
            } else {
                setIfChanged(service, accelerationKey, acceleration)
            }
        }
    }

    /// Puts back each mouse's own values.
    func restore() {
        for service in mice() {
            guard let values = originals[registryID(of: service)] else { continue }
            // Resolution first: acceleration must be written after it to take effect.
            for key in [Self.linearScalingKey, Self.resolutionKey, accelerationKey(of: service)] {
                if let value = values[key] { IOHIDServiceClientSetProperty(service, key as CFString, value) }
            }
        }
        originals.removeAll()
    }

    private func mice() -> [IOHIDServiceClient] {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return services.filter { service in
            guard IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0 else {
                return false
            }
            let isTouchpad = IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) != 0
            return DeviceKind.classify(vendorID: property(service, "VendorID") as? Int,
                                       productID: property(service, "ProductID") as? Int,
                                       isTouchpad: isTouchpad) == .mouse
        }
    }

    private func accelerationKey(of service: IOHIDServiceClient) -> String {
        property(service, "HIDPointerAccelerationType") as? String ?? "HIDMouseAcceleration"
    }

    private func registryID(of service: IOHIDServiceClient) -> String {
        "\(IOHIDServiceClientGetRegistryID(service))"
    }

    private func property(_ service: IOHIDServiceClient, _ key: String) -> CFTypeRef? {
        IOHIDServiceClientCopyProperty(service, key as CFString)
    }

    @discardableResult
    private func setIfChanged(_ service: IOHIDServiceClient, _ key: String, _ value: Int) -> Bool {
        guard (property(service, key) as? Int) != value else { return false }
        set(service, key, value)
        return true
    }

    private func set(_ service: IOHIDServiceClient, _ key: String, _ value: Int) {
        IOHIDServiceClientSetProperty(service, key as CFString, value as NSNumber)
    }
}
