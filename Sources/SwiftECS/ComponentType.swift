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
        self.name = ComponentTypeNames.name(of: type)
    }

    // Identity is the type alone; `name` is for debugging. Hashing the name made every archetype lookup hash
    // strings (#46).
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// String(describing:) is slow, and ComponentType is made on hot paths, so each type's name is made once.
private enum ComponentTypeNames {
    private static let lock = ScopedLock()
    nonisolated(unsafe) private static var names: [ObjectIdentifier: String] = [:]

    static func name<T>(of type: T.Type) -> String {
        let id = ObjectIdentifier(type)
        if let name = lock.withLock({ names[id] }) {
            return name
        }
        let name = String(describing: type)
        lock.withLock { names[id] = name }
        return name
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
