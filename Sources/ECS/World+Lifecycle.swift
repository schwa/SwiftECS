extension World {
    @discardableResult
    public func destroy(_ entity: Entity) -> Bool {
        guard entity.world === self else {
            return false
        }
        return removeEntity(entity.id)
    }

    public func clone(_ entity: Entity) -> Entity? {
        guard entity.world === self else {
            return nil
        }
        return cloneEntity(entity.id)
    }

    @discardableResult
    public func destroyRecursively(_ entity: Entity) -> Int {
        destroyRecursively(entity, following: ChildOf.self)
    }

    @discardableResult
    public func destroyRecursively<R: Relationship>(_ entity: Entity, following type: R.Type) -> Int {
        guard entity.world === self, entity.exists else {
            return 0
        }
        let ids = [entity.id] + entity.descendants(via: type).map(\.id)
        return removeEntities(ids.reversed())
    }
}
