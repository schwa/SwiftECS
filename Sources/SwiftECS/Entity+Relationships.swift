extension Entity {
    /// The entity's ``ChildOf`` target, or `nil` if it has no parent.
    public var parent: Entity? {
        targets(of: ChildOf.self).first
    }

    /// The entities whose parent is this entity.
    public var children: [Entity] {
        sources(of: ChildOf.self)
    }

    /// Sets or clears the entity's parent.
    ///
    /// - Parameter parent: The new parent, or `nil` to remove the current one.
    /// - Throws: ``RelationshipError`` if an entity is missing, from another world, or the link makes a cycle.
    public func setParent(_ parent: Entity?) throws {
        if let parent {
            try addRelationship(ChildOf.self, to: parent)
        } else {
            try world.validateRelationshipEntity(self)
            let type = RelationshipType(ChildOf.self)
            guard world.relationshipGraph.contains(type, source: id, target: nil) else {
                return
            }
            let removed = world.relationshipGraph.targets(type, from: id)
            world.mutations.perform({
                world.relationshipGraph.removeOutgoing(type, source: id)
            }, events: {
                for target in removed {
                    world.mutations.relationshipChanged(type, .removed(source: id, target: target))
                }
            })
        }
    }

    /// Adds a link from this entity to the target. Does nothing if the link exists.
    ///
    /// For an exclusive relationship, the new link replaces the current one.
    ///
    /// - Throws: ``RelationshipError`` if an entity is missing, from another world, or the link makes a cycle in
    ///   an acyclic relationship.
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
        let removed = R.isExclusive && world.mutations.hasRelationshipObservers(relationshipType)
            ? graph.targets(relationshipType, from: id) : []
        world.mutations.perform({
            if R.isExclusive {
                graph.removeOutgoing(relationshipType, source: id)
            }
            graph.insert(relationshipType, source: id, target: target.id)
        }, events: {
            for previous in removed {
                world.mutations.relationshipChanged(relationshipType, .removed(source: id, target: previous))
            }
            world.mutations.relationshipChanged(relationshipType, .added(source: id, target: target.id))
        })
    }

    /// Removes the link from this entity to the target.
    ///
    /// - Returns: `true` if a link was removed.
    /// - Throws: ``RelationshipError`` if an entity is missing or from another world.
    @discardableResult
    public func removeRelationship<R: Relationship>(_ type: R.Type, to target: Entity) throws -> Bool {
        try world.validateRelationshipEntity(self)
        try world.validateRelationshipEntity(target)
        let relationshipType = RelationshipType(type)
        guard world.relationshipGraph.contains(relationshipType, source: id, target: target.id) else {
            return false
        }
        world.mutations.perform({
            world.relationshipGraph.remove(relationshipType, source: id, target: target.id)
        }, events: {
            world.mutations.relationshipChanged(relationshipType, .removed(source: id, target: target.id))
        })
        return true
    }

    /// Returns the entities this entity links to.
    public func targets<R: Relationship>(of type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return world.relationshipGraph.targets(RelationshipType(type), from: id).map { Entity(id: $0, world: world) }
    }

    /// Returns the entities that link to this entity.
    public func sources<R: Relationship>(of type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return world.relationshipGraph.sources(RelationshipType(type), to: id).map { Entity(id: $0, world: world) }
    }

    /// Whether this entity links to the target.
    public func hasRelationship<R: Relationship>(_ type: R.Type, to target: Entity) -> Bool {
        world.trackStorageAccess()
        guard world === target.world else {
            return false
        }
        return world.relationshipGraph.contains(RelationshipType(type), source: id, target: target.id)
    }

    /// Returns the entities reachable by following links from this entity, nearest first.
    public func ancestors<R: Relationship>(via type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return world.relationshipGraph.traverse(RelationshipType(type), from: id, reversed: false).map { Entity(id: $0, world: world) }
    }

    /// Returns the entities that reach this entity by following links, in breadth-first order.
    public func descendants<R: Relationship>(via type: R.Type) -> [Entity] {
        world.trackStorageAccess()
        return world.relationshipGraph.traverse(RelationshipType(type), from: id, reversed: true).map { Entity(id: $0, world: world) }
    }

    /// Returns the entity's parent, grandparent, and so on.
    public func ancestors() -> [Entity] {
        ancestors(via: ChildOf.self)
    }

    /// Returns the entity's children, grandchildren, and so on, in breadth-first order.
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
