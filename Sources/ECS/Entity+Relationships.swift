extension Entity {
    public var parent: Entity? {
        targets(of: ChildOf.self).first
    }

    public var children: [Entity] {
        sources(of: ChildOf.self)
    }

    public func setParent(_ parent: Entity?) throws {
        if let parent {
            try addRelationship(ChildOf.self, to: parent)
        } else {
            try world.validateRelationshipEntity(self)
            let type = RelationshipType(ChildOf.self)
            guard let storage = world.relationships[type], !storage.targets(from: id).isEmpty else {
                return
            }
            storage.removeOutgoing(from: id)
            world.storageDidChange()
        }
    }

    public func addRelationship<R: Relationship>(_ type: R.Type, to target: Entity) throws {
        try world.validateRelationshipEntity(self)
        try world.validateRelationshipEntity(target)
        let relationshipType = RelationshipType(type)
        let storage = world.relationships[relationshipType] ?? RelationshipStorage()
        if storage.contains(source: id, target: target.id) {
            return
        }
        if R.isAcyclic, storage.reaches(from: target.id, to: id) {
            throw RelationshipError.cycleDetected(relationshipType)
        }
        if R.isExclusive {
            storage.removeOutgoing(from: id)
        }
        storage.insert(source: id, target: target.id)
        world.relationships[relationshipType] = storage
        world.storageDidChange()
    }

    @discardableResult
    public func removeRelationship<R: Relationship>(_ type: R.Type, to target: Entity) throws -> Bool {
        try world.validateRelationshipEntity(self)
        try world.validateRelationshipEntity(target)
        guard world.relationships[RelationshipType(type)]?.remove(source: id, target: target.id) == true else {
            return false
        }
        world.storageDidChange()
        return true
    }

    public func targets<R: Relationship>(of type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return (world.relationships[RelationshipType(type)]?.targets(from: id) ?? []).map { Entity(id: $0, world: world) }
    }

    public func sources<R: Relationship>(of type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return (world.relationships[RelationshipType(type)]?.sources(to: id) ?? []).map { Entity(id: $0, world: world) }
    }

    public func hasRelationship<R: Relationship>(_ type: R.Type, to target: Entity) -> Bool {
        world.trackStorageAccess()
        guard world === target.world else {
            return false
        }
        return world.relationships[RelationshipType(type)]?.contains(source: id, target: target.id) == true
    }

    public func ancestors<R: Relationship>(via type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return (world.relationships[RelationshipType(type)]?.traverse(from: id, reversed: false) ?? []).map { Entity(id: $0, world: world) }
    }

    public func descendants<R: Relationship>(via type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return (world.relationships[RelationshipType(type)]?.traverse(from: id, reversed: true) ?? []).map { Entity(id: $0, world: world) }
    }

    public func ancestors() -> [Entity] {
        ancestors(via: ChildOf.self)
    }

    public func descendants() -> [Entity] {
        descendants(via: ChildOf.self)
    }

    @discardableResult
    public func destroyRecursively() -> Int {
        destroyRecursively(following: ChildOf.self)
    }

    @discardableResult
    public func destroyRecursively<R: Relationship>(following type: R.Type) -> Int {
        guard exists else {
            return 0
        }
        let ids = [id] + descendants(via: type).map(\.id)
        return world.removeEntities(ids.reversed())
    }
}

extension World {
    internal func validateRelationshipEntity(_ entity: Entity) throws {
        guard entity.world === self else {
            throw RelationshipError.differentWorlds
        }
        guard entityLocations[entity.id] != nil else {
            throw RelationshipError.missingEntity(entity.id)
        }
    }
}
