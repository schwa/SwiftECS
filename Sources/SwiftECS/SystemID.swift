/// A unique identifier for a system.
public struct SystemID: Hashable, Equatable, Sendable {
    /// The underlying string value.
    public let value: String

    /// Create a system ID from a string.
    public init(_ value: String) {
        self.value = value
    }
}

// MARK: - ExpressibleByStringLiteral

extension SystemID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}

// MARK: - CustomStringConvertible

extension SystemID: CustomStringConvertible {
    public var description: String {
        value
    }
}

// MARK: - Convenience

extension SystemID {
    /// Create a system ID from a type name.
    public static func of<T>(_ type: T.Type) -> SystemID {
        SystemID(String(describing: type))
    }
}
