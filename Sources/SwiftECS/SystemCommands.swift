public struct SystemCommands {
    internal let scope: SystemScope

    @discardableResult
    public func create<each Value: Component>(_ components: repeat each Value) throws -> EntityID {
        scope.checkActive()
        for type in repeat (each Value).self {
            guard !(type is AnyObject.Type) else {
                throw SystemError.referenceComponent(ComponentType(type))
            }
        }
        var id = EntityID()
        while scope.world.entityExists(id) || scope.reservedIDs.contains(id) {
            id = EntityID()
        }
        scope.reservedIDs.insert(id)
        scope.commands.append { world in
            world.createEntity(id: id, repeat each components)
        }
        return id
    }

    public func destroy(_ id: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            world.removeEntity(id)
        }
    }

    public func addRelationship<R: Relationship>(_ type: R.Type, from source: EntityID, to target: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            try Entity(id: source, world: world).addRelationship(type, to: Entity(id: target, world: world))
        }
    }

    public func removeRelationship<R: Relationship>(_ type: R.Type, from source: EntityID, to target: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            try Entity(id: source, world: world).removeRelationship(type, to: Entity(id: target, world: world))
        }
    }
}
