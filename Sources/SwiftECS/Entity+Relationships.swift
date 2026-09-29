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
            guard world.relationshipGraph.contains(type, source: id, target: nil) else {
                return
            }
            world.mutations.perform {
                world.relationshipGraph.removeOutgoing(type, source: id)
            }
        }
    }

    public func addRelationship<R: Relationship>(_ type: R.Type, to target: Entity) throws {
        try world.validateRelationshipEntity(self)
        try world.validateRelationshipEntity(target)
        let relationshipType = RelationshipType(type)
        let graph = world.relationshipGraph
        if graph.contains(relationshipType, source: id, target: target.id) {
            return
        }
        if R.isAcyclic, graph.reaches(relationshipType, from: target.id, to: id) {
            throw RelationshipError.cycleDetected(relationshipType)
        }
        world.mutations.perform {
            if R.isExclusive {
                graph.removeOutgoing(relationshipType, source: id)
            }
            graph.insert(relationshipType, source: id, target: target.id)
        }
    }

    @discardableResult
    public func removeRelationship<R: Relationship>(_ type: R.Type, to target: Entity) throws -> Bool {
        try world.validateRelationshipEntity(self)
        try world.validateRelationshipEntity(target)
        let relationshipType = RelationshipType(type)
        guard world.relationshipGraph.contains(relationshipType, source: id, target: target.id) else {
            return false
        }
        world.mutations.perform {
            world.relationshipGraph.remove(relationshipType, source: id, target: target.id)
        }
        return true
    }

    public func targets<R: Relationship>(of type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return world.relationshipGraph.targets(RelationshipType(type), from: id).map { Entity(id: $0, world: world) }
    }

    public func sources<R: Relationship>(of type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return world.relationshipGraph.sources(RelationshipType(type), to: id).map { Entity(id: $0, world: world) }
    }

    public func hasRelationship<R: Relationship>(_ type: R.Type, to target: Entity) -> Bool {
        world.trackStorageAccess()
        guard world === target.world else {
            return false
        }
        return world.relationshipGraph.contains(RelationshipType(type), source: id, target: target.id)
    }

    public func ancestors<R: Relationship>(via type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return world.relationshipGraph.traverse(RelationshipType(type), from: id, reversed: false).map { Entity(id: $0, world: world) }
    }

    public func descendants<R: Relationship>(via type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return world.relationshipGraph.traverse(RelationshipType(type), from: id, reversed: true).map { Entity(id: $0, world: world) }
    }

    public func ancestors() -> [Entity] {
        ancestors(via: ChildOf.self)
    }

    public func descendants() -> [Entity] {
        descendants(via: ChildOf.self)
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
