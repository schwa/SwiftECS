/// Unrestricted deferred commands. Supplied by ``Commands``.
///
/// Commands run in order when the system's commands merge. They are discarded if the callback throws.
public struct SystemCommands {
    internal let scope: SystemScope

    /// Reserves an ID and creates an entity with the given components when commands merge.
    ///
    /// - Returns: The new entity's ID, usable as a target in later commands.
    /// - Throws: ``SystemError/referenceComponent(_:)`` if a component is a class.
    @discardableResult
    public func create<each Value: Component>(_ components: repeat each Value) throws -> EntityID {
        scope.checkActive()
        for type in repeat (each Value).self {
            guard !(type is AnyObject.Type) else {
                throw SystemError.referenceComponent(ComponentType(type))
            }
        }
        var id = EntityID()
        while scope.world.entityExists(id) || scope.world.reservedCommandIDs.contains(id) {
            id = EntityID()
        }
        scope.reservedIDs.insert(id)
        scope.world.reservedCommandIDs.insert(id)
        scope.commands.append { world in
            world.createEntity(id: id, repeat each components)
        }
        return id
    }

    /// Destroys an entity. Does nothing if it no longer exists.
    public func destroy(_ id: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            world.removeEntity(id)
        }
    }

    /// Sets a component on an entity.
    ///
    /// - Throws: ``SystemError/referenceComponent(_:)`` if the component is a class, or
    ///   ``SystemError/missingCommandEntity(_:)`` during the merge if the entity no longer exists.
    public func set<Value: Component>(_ value: Value, on id: EntityID) throws {
        scope.checkActive()
        guard !(Value.self is AnyObject.Type) else {
            throw SystemError.referenceComponent(ComponentType(Value.self))
        }
        scope.commands.append { world in
            guard world.entityExists(id) else {
                throw SystemError.missingCommandEntity(id)
            }
            world.addComponent(value, to: id)
        }
    }

    /// Removes a component from an entity. Does nothing if it is absent.
    public func remove<Value: Component>(_ type: Value.Type, from id: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            world.removeComponent(type, from: id)
        }
    }

    /// Adds a relationship link.
    public func addRelationship<R: Relationship>(_ type: R.Type, from source: EntityID, to target: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            try Entity(id: source, world: world).addRelationship(type, to: Entity(id: target, world: world))
        }
    }

    /// Removes a relationship link.
    public func removeRelationship<R: Relationship>(_ type: R.Type, from source: EntityID, to target: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            try Entity(id: source, world: world).removeRelationship(type, to: Entity(id: target, world: world))
        }
    }
}
