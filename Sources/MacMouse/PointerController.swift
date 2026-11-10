import CPrivate
import Foundation
import IOKit.hid
import MacMouseCore

/// Finds pointing devices and sets pointer speed and acceleration on the mice the settings
/// apply to, through the HID event system, the way LinearMouse does. Needs no permission.
final class PointerController {
    private static let resolutionKey = "HIDPointerResolution"
    private static let linearScalingKey = "HIDUseLinearScalingMouseAcceleration"
    private static let fallbackAcceleration = 0.6875
    private static let fallbackResolution = 400.0

    private static let reconnectInterval: TimeInterval = 5

    let registry = DeviceRegistry()
    /// Called on the main thread when a HID service appears, such as a mouse or receiver that
    /// connects after launch.
    var onServicesAdded: () -> Void = {}
    private var client: IOHIDEventSystemClient?
    private var lastConnect = -Double.infinity

    private struct Baseline {
        var resolution: Int?
        var linearScaling: Int?
    }
    /// Values before this app changed a mouse, by registry ID, like LinearMouse's initial values.
    private var baselines: [UInt64: Baseline] = [:]

    /// Every connected mouse, for the settings window.
    private(set) var connectedMice: [DeviceMatch] = []
    /// Names of the connected mice the settings apply to.
    private(set) var matchedNames: [String] = []

    init() {
        connect()
    }

    /// Replaces the event system client. An unscheduled client keeps the service list it had when
    /// it was created, so a mouse behind a dock that enumerates after login would never be found;
    /// a client scheduled on the main run loop keeps its list current and reports new services.
    private func connect() {
        if let client { IOHIDEventSystemClientUnscheduleWithRunLoop(client, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) }
        lastConnect = ProcessInfo.processInfo.systemUptime
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        guard let client else { return }
        IOHIDEventSystemClientRegisterDeviceMatchingCallback(client, { _, refcon, _ in
            Unmanaged<PointerController>.fromOpaque(refcon!).takeUnretainedValue().onServicesAdded()
        }, nil, Unmanaged.passUnretained(self).toOpaque())
        IOHIDEventSystemClientScheduleWithRunLoop(client, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    /// Input from a HID service the client does not list means its list went stale; a new client
    /// lists every current service. Limited to one reconnect per few seconds in case some sender
    /// is never listed.
    func reconnectIfUnlisted(sender: UInt64) {
        guard ProcessInfo.processInfo.systemUptime - lastConnect > Self.reconnectInterval else { return }
        let listed = (client.flatMap { IOHIDEventSystemClientCopyServices($0) } as? [IOHIDServiceClient] ?? [])
            .contains { registryID(of: $0) == sender }
        if !listed { connect() }
    }

    /// Refreshes the device list and writes values that differ, so it is cheap to call often; it
    /// also undoes resets by System Settings or a reconnecting mouse.
    func apply(_ settings: MouseSettings, enabled: Bool) {
        var pointerIDs: Set<UInt64> = [], matchedIDs: Set<UInt64> = []
        var mice: [DeviceMatch] = [], names: [String] = []
        for service in pointingServices() {
            guard let id = registryID(of: service) else { continue }
            pointerIDs.insert(id)
            let identity = DeviceMatch(vendorID: int(service, kIOHIDVendorIDKey), productID: int(service, kIOHIDProductIDKey),
                                       productName: property(service, kIOHIDProductKey) as? String)
            guard kind(of: service) == .mouse else { continue }
            mice.append(identity)
            if settings.device.matches(vendorID: identity.vendorID, productID: identity.productID, productName: identity.productName) {
                matchedIDs.insert(id)
                names.append(identity.productName ?? "Mouse")
                if enabled {
                    apply(settings, to: service, id: id)
                } else {
                    restore(service, id: id)
                }
            } else {
                restore(service, id: id)
            }
        }
        registry.replace(pointerIDs: pointerIDs, matchedIDs: enabled ? matchedIDs : [])
        connectedMice = Array(Set(mice)).sorted { $0.title < $1.title }
        matchedNames = Array(Set(names)).sorted()
        baselines = baselines.filter { pointerIDs.contains($0.key) }
    }

    /// Puts back every changed mouse's own values.
    func restoreAll() {
        for service in pointingServices() {
            if let id = registryID(of: service) { restore(service, id: id) }
        }
    }

    // MARK: Applying, as LinearMouse's PointerSchemeApplier

    private func apply(_ settings: MouseSettings, to service: IOHIDServiceClient, id: UInt64) {
        if baselines[id] == nil {
            baselines[id] = Baseline(resolution: int(service, Self.resolutionKey), linearScaling: int(service, Self.linearScalingKey))
        }
        let supportsLinearScaling = baselines[id]?.linearScaling != nil
        let accelerationKey = accelerationKey(of: service)
        if supportsLinearScaling {
            setIfChanged(service, Self.linearScalingKey, settings.disablePointerAcceleration ? 1 : 0)
        }
        if settings.disablePointerAcceleration {
            // Speed is not applied while acceleration is disabled.
            if !supportsLinearScaling { setIfChanged(service, accelerationKey, Int(PointerMath.fixed(-1))) }
            return
        }
        let resolution = Int(PointerMath.fixed(min(max(PointerMath.resolution(forSpeed: settings.pointerSpeed), 10), 1995)))
        let acceleration = Int(PointerMath.fixed(min(max(settings.pointerAcceleration, 0), 40)))
        // A new resolution takes effect only once acceleration is written again.
        if setIfChanged(service, Self.resolutionKey, resolution) {
            set(service, accelerationKey, acceleration)
        } else {
            setIfChanged(service, accelerationKey, acceleration)
        }
    }

    /// Restores the initial resolution, the system's acceleration and the initial linear scaling,
    /// like LinearMouse when it stops managing a device.
    private func restore(_ service: IOHIDServiceClient, id: UInt64) {
        guard let baseline = baselines.removeValue(forKey: id) else { return }
        if let linearScaling = baseline.linearScaling { setIfChanged(service, Self.linearScalingKey, linearScaling) }
        set(service, Self.resolutionKey, baseline.resolution ?? Int(PointerMath.fixed(Self.fallbackResolution)))
        let key = accelerationKey(of: service)
        let system = client.flatMap { IOHIDEventSystemClientCopyProperty($0, key as CFString) as? Int }
        set(service, key, system ?? Int(PointerMath.fixed(Self.fallbackAcceleration)))
    }

    // MARK: Devices

    /// Services LinearMouse manages: anything with the generic desktop mouse or pointer usage.
    private func pointingServices() -> [IOHIDServiceClient] {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return services.filter { service in
            [kHIDUsage_GD_Mouse, kHIDUsage_GD_Pointer].contains { usage in
                IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(usage)) != 0
            }
        }
    }

    private func kind(of service: IOHIDServiceClient) -> DeviceKind {
        let isTouchpad = IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) != 0
        return DeviceKind.classify(vendorID: int(service, kIOHIDVendorIDKey), productID: int(service, kIOHIDProductIDKey),
                                   isTouchpad: isTouchpad)
    }

    /// LinearMouse's pointerAccelerationType: the declared type, else a guess.
    private func accelerationKey(of service: IOHIDServiceClient) -> String {
        if let type = property(service, "HIDPointerAccelerationType") as? String { return type }
        if int(service, "HIDPointerAcceleration") != nil { return "HIDPointerAcceleration" }
        return "HIDMouseAcceleration"
    }

    private func registryID(of service: IOHIDServiceClient) -> UInt64? {
        (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value
    }

    private func property(_ service: IOHIDServiceClient, _ key: String) -> CFTypeRef? {
        IOHIDServiceClientCopyProperty(service, key as CFString)
    }

    private func int(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        property(service, key) as? Int
    }

    @discardableResult
    private func setIfChanged(_ service: IOHIDServiceClient, _ key: String, _ value: Int) -> Bool {
        guard int(service, key) != value else { return false }
        set(service, key, value)
        return true
    }

    private func set(_ service: IOHIDServiceClient, _ key: String, _ value: Int) {
        IOHIDServiceClientSetProperty(service, key as CFString, NSNumber(value: Int32(truncatingIfNeeded: value)))
    }
}
