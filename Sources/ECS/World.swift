/// Container for entities, components, and systems.
public final class World {
    private var nextEntityID: UInt64 = 0
    private var systems: [System] = []
    private var archetypes: [ArchetypeSignature: Archetype] = [:]
    private var entityLocations: [EntityID: EntityLocation] = [:]
    private let emptySignature = ArchetypeSignature()

    /// Create an empty world.
    public init() {
        archetypes[emptySignature] = Archetype(signature: emptySignature)
    }

    // MARK: - Entity Management

    /// Create an entity with no components.
    @discardableResult
    public func createEntity() -> Entity {
        let id = EntityID(nextEntityID)
        nextEntityID += 1

        let archetype = archetypes[emptySignature]!
        let index = archetype.addEntity(id)
        entityLocations[id] = EntityLocation(signature: emptySignature, index: index)

        return Entity(id: id, world: self)
    }

    /// Create an entity with components.
    @discardableResult
    public func createEntity<each T: Component>(_ components: repeat each T) -> Entity {
        let id = EntityID(nextEntityID)
        nextEntityID += 1

        var typeIDs = Set<ObjectIdentifier>()
        for typeID in repeat ObjectIdentifier((each T).self) {
            typeIDs.insert(typeID)
        }

        let signature = ArchetypeSignature(typeIDs)
        let archetype = getOrCreateArchetype(signature)
        let index = archetype.addEntity(id)
        repeat archetype.setComponent(each components, at: index)
        entityLocations[id] = EntityLocation(signature: signature, index: index)

        return Entity(id: id, world: self)
    }

    /// Remove an entity.
    @discardableResult
    internal func removeEntity(_ id: EntityID) -> Bool {
        guard let location = entityLocations.removeValue(forKey: id) else { return false }
        guard let archetype = archetypes[location.signature] else { return false }

        if let movedEntity = archetype.removeEntity(at: location.index) {
            entityLocations[movedEntity]?.index = location.index
        }

        return true
    }

    /// Check if an entity exists.
    public func entityExists(_ id: EntityID) -> Bool {
        entityLocations[id] != nil
    }

    /// Get an entity handle.
    public subscript(id: EntityID) -> Entity? {
        guard entityExists(id) else { return nil }
        return Entity(id: id, world: self)
    }

    /// Number of entities.
    public var entityCount: Int {
        entityLocations.count
    }

    // MARK: - Component Access (Internal)

    internal func addComponent<T: Component>(_ component: T, to entityID: EntityID) {
        guard let location = entityLocations[entityID] else { return }
        let typeID = ObjectIdentifier(T.self)

        if location.signature.contains(typeID) {
            if let archetype = archetypes[location.signature] {
                archetype.setComponent(component, at: location.index)
            }
            return
        }

        let newSignature = location.signature.adding(typeID)
        moveEntity(entityID, from: location, to: newSignature, addingComponent: component)
    }

    internal func component<T: Component>(_ type: T.Type, for entityID: EntityID) -> T? {
        guard let location = entityLocations[entityID],
              let archetype = archetypes[location.signature] else { return nil }
        return archetype.getComponent(type, at: location.index)
    }

    @discardableResult
    internal func removeComponent<T: Component>(_ type: T.Type, from entityID: EntityID) -> T? {
        guard let location = entityLocations[entityID] else { return nil }
        let typeID = ObjectIdentifier(T.self)

        guard location.signature.contains(typeID) else { return nil }

        let value = archetypes[location.signature]?.getComponent(type, at: location.index)

        let newSignature = location.signature.removing(typeID)
        moveEntity(entityID, from: location, to: newSignature, removingType: typeID)

        return value
    }

    internal func hasComponent<T: Component>(_ type: T.Type, for entityID: EntityID) -> Bool {
        guard let location = entityLocations[entityID] else { return false }
        return location.signature.contains(ObjectIdentifier(type))
    }

    // MARK: - Archetype Management (Private)

    private func getOrCreateArchetype(_ signature: ArchetypeSignature) -> Archetype {
        if let existing = archetypes[signature] {
            return existing
        }
        let archetype = Archetype(signature: signature)
        archetypes[signature] = archetype
        return archetype
    }

    private func moveEntity<T: Component>(
        _ entityID: EntityID,
        from oldLocation: EntityLocation,
        to newSignature: ArchetypeSignature,
        addingComponent newComponent: T
    ) {
        guard let oldArchetype = archetypes[oldLocation.signature] else { return }
        let newArchetype = getOrCreateArchetype(newSignature)

        let newIndex = newArchetype.addEntity(entityID)
        oldArchetype.copyComponents(at: oldLocation.index, to: newArchetype, targetIndex: newIndex)
        newArchetype.setComponent(newComponent, at: newIndex)

        if let movedEntity = oldArchetype.removeEntity(at: oldLocation.index) {
            entityLocations[movedEntity]?.index = oldLocation.index
        }

        entityLocations[entityID] = EntityLocation(signature: newSignature, index: newIndex)
    }

    private func moveEntity(
        _ entityID: EntityID,
        from oldLocation: EntityLocation,
        to newSignature: ArchetypeSignature,
        removingType: ObjectIdentifier
    ) {
        guard let oldArchetype = archetypes[oldLocation.signature] else { return }
        let newArchetype = getOrCreateArchetype(newSignature)

        let newIndex = newArchetype.addEntity(entityID)
        oldArchetype.copyComponents(at: oldLocation.index, to: newArchetype, targetIndex: newIndex, excludeType: removingType)

        if let movedEntity = oldArchetype.removeEntity(at: oldLocation.index) {
            entityLocations[movedEntity]?.index = oldLocation.index
        }

        entityLocations[entityID] = EntityLocation(signature: newSignature, index: newIndex)
    }

    // MARK: - Iteration

    // TODO: Swift compiler crashes (signal 5) in SILGen when using parameter packs with Composite.
    // This would be the ideal variadic forEach using Composite to bundle components.
    // Crashes in emitPackExpansionIntoPack - tested with Swift 6.0, 6.1, 6.2.
    // See: https://github.com/swiftlang/swift/issues
    //
    // public func forEach<each T: Component>(
    //     _ types: repeat (each T).Type,
    //     body: (Entity, Composite<repeat each T>) -> Void
    // ) {
    //     var typeIDs = Set<ObjectIdentifier>()
    //     for typeID in repeat ObjectIdentifier((each T).self) {
    //         typeIDs.insert(typeID)
    //     }
    //
    //     for archetype in archetypes.values {
    //         guard archetype.signature.isSuperset(of: typeIDs) else { continue }
    //
    //         let columns = (repeat archetype.column(for: (each T).self))
    //         var allPresent = true
    //         for col in repeat each columns {
    //             if col == nil { allPresent = false }
    //         }
    //         guard allPresent else { continue }
    //
    //         for i in 0..<archetype.entities.count {
    //             let components = Composite(repeat (each columns)!.data[i])
    //             body(Entity(id: archetype.entities[i], world: self), components)
    //         }
    //     }
    // }

    /// Iterate entities with one component.
    public func forEach<T: Component>(_ type: T.Type, body: (Entity, T) -> Void) {
        let typeID = ObjectIdentifier(type)
        for archetype in archetypes.values {
            guard archetype.signature.contains(typeID),
                  let col = archetype.column(for: type) else { continue }
            for i in 0..<archetype.entities.count {
                body(Entity(id: archetype.entities[i], world: self), col.data[i])
            }
        }
    }

    /// Iterate entities with two components.
    public func forEach<T1: Component, T2: Component>(
        _ type1: T1.Type, _ type2: T2.Type,
        body: (Entity, T1, T2) -> Void
    ) {
        let typeIDs: Set<ObjectIdentifier> = [ObjectIdentifier(type1), ObjectIdentifier(type2)]
        for archetype in archetypes.values {
            guard archetype.signature.isSuperset(of: typeIDs),
                  let col1 = archetype.column(for: type1),
                  let col2 = archetype.column(for: type2) else { continue }
            for i in 0..<archetype.entities.count {
                body(Entity(id: archetype.entities[i], world: self), col1.data[i], col2.data[i])
            }
        }
    }

    /// Iterate entities with one component (mutable).
    public func forEachMutable<T: Component>(_ type: T.Type, body: (Entity, inout T) -> Void) {
        let typeID = ObjectIdentifier(type)
        for archetype in archetypes.values {
            guard archetype.signature.contains(typeID),
                  let col = archetype.column(for: type) else { continue }
            for i in 0..<archetype.entities.count {
                body(Entity(id: archetype.entities[i], world: self), &col.data[i])
            }
        }
    }

    /// Iterate entities with two components (mutable).
    public func forEachMutable<T1: Component, T2: Component>(
        _ type1: T1.Type, _ type2: T2.Type,
        body: (Entity, inout T1, inout T2) -> Void
    ) {
        let typeIDs: Set<ObjectIdentifier> = [ObjectIdentifier(type1), ObjectIdentifier(type2)]
        for archetype in archetypes.values {
            guard archetype.signature.isSuperset(of: typeIDs),
                  let col1 = archetype.column(for: type1),
                  let col2 = archetype.column(for: type2) else { continue }
            for i in 0..<archetype.entities.count {
                body(Entity(id: archetype.entities[i], world: self), &col1.data[i], &col2.data[i])
            }
        }
    }

    /// Iterate entities with three components (mutable).
    public func forEachMutable<T1: Component, T2: Component, T3: Component>(
        _ type1: T1.Type, _ type2: T2.Type, _ type3: T3.Type,
        body: (Entity, inout T1, inout T2, inout T3) -> Void
    ) {
        let typeIDs: Set<ObjectIdentifier> = [
            ObjectIdentifier(type1),
            ObjectIdentifier(type2),
            ObjectIdentifier(type3)
        ]
        for archetype in archetypes.values {
            guard archetype.signature.isSuperset(of: typeIDs),
                  let col1 = archetype.column(for: type1),
                  let col2 = archetype.column(for: type2),
                  let col3 = archetype.column(for: type3) else { continue }
            for i in 0..<archetype.entities.count {
                body(Entity(id: archetype.entities[i], world: self), &col1.data[i], &col2.data[i], &col3.data[i])
            }
        }
    }

    // MARK: - Querying

    /// All entities.
    public var entities: [Entity] {
        entityLocations.keys.map { Entity(id: $0, world: self) }
    }

    /// Get entities with all specified components.
    public func entities<each T: Component>(with componentTypes: repeat (each T).Type) -> [Entity] {
        var typeIDs = Set<ObjectIdentifier>()
        for typeID in repeat ObjectIdentifier((each T).self) {
            typeIDs.insert(typeID)
        }

        var result: [Entity] = []
        for archetype in archetypes.values {
            guard archetype.signature.isSuperset(of: typeIDs) else { continue }
            for entityID in archetype.entities {
                result.append(Entity(id: entityID, world: self))
            }
        }

        return result
    }

    // MARK: - System Management

    /// Add a system.
    public func addSystem(_ system: System) {
        systems.append(system)
        system.initialize(world: self)
    }

    /// Remove all systems.
    public func removeAllSystems() {
        for system in systems {
            system.cleanup(world: self)
        }
        systems.removeAll()
    }

    /// Update all systems.
    public func update(deltaTime: Double) {
        for system in systems {
            system.update(world: self, deltaTime: deltaTime)
        }
    }
}
