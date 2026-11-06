/// Handle for accessing an entity's components.
public struct Entity: Identifiable {
    /// The unique identifier for this entity.
    public let id: EntityID
    internal let world: World

    @usableFromInline
    internal init(id: EntityID, world: World) {
        self.id = id
        self.world = world
    }

    /// Check if entity still exists.
    public var exists: Bool {
        world.entityExists(id)
    }

    /// Get the component types for this entity.
    public var componentTypes: [ComponentType] {
        world.componentTypes(for: self)
    }

    /// Get all components for this entity.
    public var allComponents: [any Component] {
        world.allComponents(for: id)
    }

    /// Get or set a component.
    public subscript<T: Component>(_ type: T.Type) -> T? {
        get {
            world.component(type, for: id)
        }
        nonmutating set {
            if let newValue {
                world.addComponent(newValue, to: id)
            } else {
                world.removeComponent(type, from: id)
            }
        }
    }

    /// Check if entity contains a component.
    public func contains<T: Component>(_ type: T.Type) -> Bool {
        world.hasComponent(type, for: id)
    }

    /// Set (add or update) a component.
    @discardableResult
    public func set<T: Component>(_ component: T) -> Entity {
        world.addComponent(component, to: id)
        return self
    }

    /// Remove a component.
    @discardableResult
    public func remove<T: Component>(_ type: T.Type) -> T? {
        world.removeComponent(type, from: id)
    }

    /// Get multiple components as a Composite.
    /// Returns nil if any of the requested components are missing.
    public func get<each T: Component>(_ types: repeat (each T).Type) -> Composite<repeat each T>? {
        for type in repeat (each types) {
            guard world.hasComponent(type, for: id) else {
                return nil
            }
        }
        return Composite(repeat requiredComponent((each T).self))
    }

    private func requiredComponent<T: Component>(_ type: T.Type) -> T {
        guard let component = world.component(type, for: id) else {
            preconditionFailure("Component \(type) is missing after the existence check")
        }
        return component
    }

    /// Set multiple components from a Composite.
    @discardableResult
    public func set<each T: Component>(_ composite: Composite<repeat each T>) -> Entity {
        repeat world.addComponent(each composite.values, to: id)
        return self
    }

    /// Set multiple components.
    @discardableResult
    public func set<each T: Component>(_ components: repeat each T) -> Entity {
        repeat world.addComponent(each components, to: id)
        return self
    }
}
