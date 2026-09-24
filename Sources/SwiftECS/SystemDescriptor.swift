public struct SystemDescriptor: Component {
    public let id: SystemID
    public var isRegistered: Bool { implementation != nil }

    internal let implementation: (any System)?
    internal let registrationOrder: UInt64
}
