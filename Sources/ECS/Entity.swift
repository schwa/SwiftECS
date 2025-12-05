/// Unique entity identifier.
public struct EntityID: Hashable, Equatable, Sendable {
    /// The underlying integer value.
    public let value: UInt64

    /// Create an entity ID from a raw value.
    public init(_ value: UInt64) {
        self.value = value
    }
}

/// Handle for accessing an entity's components.
public struct Entity {
    /// The unique identifier for this entity.
    public let id: EntityID
    internal let world: World

    init(id: EntityID, world: World) {
        self.id = id
        self.world = world
    }

    /// Check if entity still exists.
    public var exists: Bool {
        world.entityExists(id)
    }

    /// Get a component.
    public subscript<T: Component>(_ type: T.Type) -> T? {
        world.component(type, for: id)
    }

    /// Check if entity has a component.
    public func has<T: Component>(_ type: T.Type) -> Bool {
        world.hasComponent(type, for: id)
    }

    /// Add or update a component.
    @discardableResult
    public func add<T: Component>(_ component: T) -> Entity {
        world.addComponent(component, to: id)
        return self
    }

    /// Remove a component.
    @discardableResult
    public func remove<T: Component>(_ type: T.Type) -> T? {
        world.removeComponent(type, from: id)
    }

    /// Remove this entity from the world.
    @discardableResult
    public func destroy() -> Bool {
        world.removeEntity(id)
    }
}
