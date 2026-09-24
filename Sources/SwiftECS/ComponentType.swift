/// A type-erased identifier for a component type.
public struct ComponentType: Hashable, Equatable, Sendable {
    /// The underlying identifier.
    public let id: ObjectIdentifier

    /// The name of the type (for debugging).
    public let name: String

    /// Create a component type from an ObjectIdentifier.
    public init(_ id: ObjectIdentifier, name: String = "Unknown") {
        self.id = id
        self.name = name
    }

    /// Create a component type from a Component metatype.
    public init<T: Component>(_ type: T.Type) {
        self.id = ObjectIdentifier(type)
        self.name = String(describing: type)
    }
}

// MARK: - Convenience

extension ComponentType {
    /// Create a component type from a Component metatype.
    public static func of<T: Component>(_ type: T.Type) -> ComponentType {
        ComponentType(type)
    }
}

// MARK: - CustomStringConvertible

extension ComponentType: CustomStringConvertible {
    public var description: String {
        name
    }
}
