extension World {
    @discardableResult
    public func destroy(_ entity: Entity) throws(WorldError) -> Bool {
        guard entity.world === self else {
            throw .foreignEntity(entity.id)
        }
        return removeEntity(entity.id)
    }

    public func clone(_ entity: Entity) throws(WorldError) -> Entity? {
        guard entity.world === self else {
            throw .foreignEntity(entity.id)
        }
        return cloneEntity(entity.id)
    }

    @discardableResult
    public func destroyRecursively(_ entity: Entity) throws(WorldError) -> Int {
        try destroyRecursively(entity, following: ChildOf.self)
    }

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
