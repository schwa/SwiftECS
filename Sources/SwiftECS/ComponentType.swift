/// A type-erased identifier for a component type.
public struct ComponentType: Hashable, Equatable, Sendable {
    /// The underlying identifier.
    public let id: ObjectIdentifier

    // Either the type, whose name is made only when asked for, or an explicit name. ComponentType is made on hot
    // paths, so init does no string work.
    private let source: Source

    // Metatypes are immutable, so sharing one across isolation domains is safe.
    private enum Source: @unchecked Sendable {
        case type(any Component.Type)
        case name(String)
    }

    /// The name of the type (for debugging).
    public var name: String {
        switch source {
        case let .type(type):
            String(describing: type)
        case let .name(name):
            name
        }
    }

    /// Create a component type from an ObjectIdentifier.
    public init(_ id: ObjectIdentifier, name: String = "Unknown") {
        self.id = id
        self.source = .name(name)
    }

    /// Create a component type from a Component metatype.
    @inlinable
    public init<T: Component>(_ type: T.Type) {
        self.init(id: ObjectIdentifier(type), type: type)
    }

    @usableFromInline
    init(id: ObjectIdentifier, type: any Component.Type) {
        self.id = id
        self.source = .type(type)
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
