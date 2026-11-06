/// World-owned registration data stored on each system entity. Do not set, copy, or remove it.
public struct SystemDescriptor: Component {
    /// The system's identifier.
    public let id: SystemID
    /// Whether a system is registered under this ID. False for forward references from `before:` or `after:`.
    public var isRegistered: Bool { implementation != nil }

    /// The registered system's declared access, or `nil` if unregistered.
    public var access: SystemAccess? { implementation?.access }

    internal let implementation: System?
    internal let registrationOrder: UInt64
}
