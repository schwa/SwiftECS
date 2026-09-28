public struct SystemDescriptor: Component {
    public let id: SystemID
    public var isRegistered: Bool { implementation != nil }

    public var access: SystemAccess? { implementation?.access }

    internal let implementation: System?
    internal let registrationOrder: UInt64
}
