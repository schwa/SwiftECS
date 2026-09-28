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

    public func destroy(_ id: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            world.removeEntity(id)
        }
    }

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

    public func remove<Value: Component>(_ type: Value.Type, from id: EntityID) {
        scope.checkActive()
        scope.commands.append { world in
            world.removeComponent(type, from: id)
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
