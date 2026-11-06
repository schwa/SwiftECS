extension World {
    /// Destroys the entity and removes its relationships.
    ///
    /// - Returns: `false` if the entity no longer exists.
    /// - Throws: ``WorldError/foreignEntity(_:)`` if the entity belongs to another world.
    @discardableResult
    public func destroy(_ entity: Entity) throws(WorldError) -> Bool {
        guard entity.world === self else {
            throw .foreignEntity(entity.id)
        }
        return removeEntity(entity.id)
    }

    /// Creates a new entity with copies of the entity's components and outgoing links.
    ///
    /// - Returns: The clone, or `nil` if the entity no longer exists.
    /// - Throws: ``WorldError/foreignEntity(_:)`` if the entity belongs to another world.
    public func clone(_ entity: Entity) throws(WorldError) -> Entity? {
        guard entity.world === self else {
            throw .foreignEntity(entity.id)
        }
        return cloneEntity(entity.id)
    }

    /// Destroys the entity and all its ``ChildOf`` descendants.
    ///
    /// - Returns: The number of entities destroyed.
    /// - Throws: ``WorldError/foreignEntity(_:)`` if the entity belongs to another world.
    @discardableResult
    public func destroyRecursively(_ entity: Entity) throws(WorldError) -> Int {
        try destroyRecursively(entity, following: ChildOf.self)
    }

    /// Destroys the entity and every entity that reaches it through links of the given type.
    ///
    /// - Returns: The number of entities destroyed.
    /// - Throws: ``WorldError/foreignEntity(_:)`` if the entity belongs to another world.
    @discardableResult
    public func destroyRecursively<R: Relationship>(_ entity: Entity, following type: R.Type) throws(WorldError) -> Int {
        guard entity.world === self else {
            throw .foreignEntity(entity.id)
        }
        guard entity.exists else {
            return 0
        }
        let ids = [entity.id] + entity.descendants(via: type).map(\.id)
        return removeEntities(ids.reversed())
    }
}
