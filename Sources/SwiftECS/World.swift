import Observation

/// Container for entities, components, and systems.
@Observable
public final class World {
    @ObservationIgnored
    internal var nextSystemRegistrationOrder: UInt64 = 0
    @ObservationIgnored
    internal var pipelineExecutionDepth = 0
    @ObservationIgnored
    internal var pendingSystemCleanup: [System] = []
    @ObservationIgnored
    internal var archetypes: [ArchetypeSignature: Archetype] = [:]
    @ObservationIgnored
    internal var structuralRevision: UInt64 = 0
    @ObservationIgnored
    internal var entityLocations: [EntityID: EntityLocation] = [:]
    @ObservationIgnored
    private let emptySignature = ArchetypeSignature()
    @ObservationIgnored
    @usableFromInline internal let mutations = MutationCoordinator()

    @inlinable
    internal func trackStorageAccess() {
        mutations.access()
    }

    @ObservationIgnored
    internal var relationships: [RelationshipType: RelationshipStorage] = [:]

    internal func removeEntities<S: Sequence>(_ ids: S) -> Int where S.Element == EntityID {
        mutations.batch {
            var removed = 0
            for id in ids where removeEntity(id) {
                removed += 1
            }
            return removed
        }
    }

    @ObservationIgnored
    @usableFromInline internal let queries = QueryEngine()

    /// The current simulation time (accumulated deltaTime from all updates).
    /// This is observable and updates once per `update()` call.
    public private(set) var simulationTime: Double = 0.0

    public var defaultPipeline = Pipeline()

    /// Create an empty world.
    public init() {
        archetypes[emptySignature] = Archetype(signature: emptySignature)
    }

    // MARK: - Entity Management

    /// Create an entity with no components.
    @discardableResult
    public func createEntity() -> Entity {
        let id = generateUniqueEntityID()
        mutations.perform {
            let archetype = archetypes[emptySignature]!
            let index = archetype.addEntity(id)
            entityLocations[id] = EntityLocation(signature: emptySignature, index: index)
            structuralRevision &+= 1
        }
        return Entity(id: id, world: self)
    }

    /// Create an entity with components.
    @discardableResult
    public func createEntity<each T: Component>(_ components: repeat each T) -> Entity {
        createEntity(id: generateUniqueEntityID(), repeat each components)
    }

    @discardableResult
    internal func createEntity<each T: Component>(id: EntityID, _ components: repeat each T) -> Entity {
        precondition(entityLocations[id] == nil, "Entity ID already exists")
        var typeIDs = Set<ComponentType>()
        for typeID in repeat ComponentType((each T).self) {
            typeIDs.insert(typeID)
        }
        let signature = ArchetypeSignature(typeIDs)
        mutations.perform {
            let archetype = getOrCreateArchetype(signature)
            let index = archetype.addEntity(id)
            repeat archetype.setComponent(each components, at: index)
            entityLocations[id] = EntityLocation(signature: signature, index: index)
            structuralRevision &+= 1
        }
        return Entity(id: id, world: self)
    }

    /// Remove an entity.
    @discardableResult
    internal func removeEntity(_ id: EntityID) -> Bool {
        guard let location = entityLocations[id], let archetype = archetypes[location.signature] else {
            return false
        }
        let implementation = component(SystemDescriptor.self, for: id)?.implementation
        mutations.perform {
            entityLocations.removeValue(forKey: id)
            structuralRevision &+= 1
            for storage in relationships.values {
                storage.removeEntity(id)
            }
            if let movedEntity = archetype.removeEntity(at: location.index) {
                entityLocations[movedEntity]?.index = location.index
            }
        }
        if let implementation {
            if pipelineExecutionDepth > 0 {
                pendingSystemCleanup.append(implementation)
            } else {
                implementation.cleanup()
            }
        }
        return true
    }

    /// Clone an entity, creating a new entity with copies of all components.
    @discardableResult
    internal func cloneEntity(_ id: EntityID) -> Entity? {
        guard component(SystemDescriptor.self, for: id) == nil, let location = entityLocations[id],
              let sourceArchetype = archetypes[location.signature] else { return nil }

        let newID = generateUniqueEntityID()
        mutations.perform {
            let targetArchetype = getOrCreateArchetype(location.signature)
            let newIndex = targetArchetype.addEntity(newID)
            sourceArchetype.copyComponents(at: location.index, to: targetArchetype, targetIndex: newIndex)
            entityLocations[newID] = EntityLocation(signature: location.signature, index: newIndex)
            structuralRevision &+= 1
            for storage in relationships.values {
                for target in storage.targets(from: id) {
                    storage.insert(source: newID, target: target)
                }
            }
        }

        return Entity(id: newID, world: self)
    }

    /// Check if an entity exists.
    public func entityExists(_ id: EntityID) -> Bool {
        trackStorageAccess()
        return entityLocations[id] != nil
    }

    /// Get an entity handle.
    public subscript(id: EntityID) -> Entity? {
        guard entityExists(id) else { return nil }
        return Entity(id: id, world: self)
    }

    /// Number of entities.
    public var entityCount: Int {
        trackStorageAccess()
        return entityLocations.count
    }

    /// All entities in the world.
    public var entities: [Entity] {
        trackStorageAccess()
        return entityLocations.keys.map { Entity(id: $0, world: self) }
    }

    // MARK: - Entity ID Generation (Private)

    private func generateUniqueEntityID() -> EntityID {
        var id = EntityID()
        while entityLocations[id] != nil {
            id = EntityID()
        }
        return id
    }

    // MARK: - Component Observers

    /// Register an observer for component events.
    /// Returns a token that can be used to unregister the observer.
    @discardableResult
    public func observe<T: Component>(
        _ type: T.Type,
        handler: @escaping (ComponentEvent<T>) -> Void
    ) -> ObservationToken {
        mutations.observe(type, handler: handler)
    }

    /// Unregister an observer.
    public func removeObserver(_ token: ObservationToken) {
        mutations.removeObserver(token)
    }

    /// Notify observers of a component change.
    @inlinable
    internal func notifyChanged<T: Component>(entityID: EntityID, component: T) {
        guard mutations.hasObservers else { return }
        mutations.changed(entity: Entity(id: entityID, world: self), component: component)
    }

    // MARK: - Component Access (Internal)

    internal func addComponent<T: Component>(_ component: T, to entityID: EntityID) {
        guard let location = entityLocations[entityID], let archetype = archetypes[location.signature] else {
            return
        }
        let typeID = ComponentType(T.self)
        let isNewComponent = !location.signature.contains(typeID)
        mutations.perform({
            if isNewComponent {
                let newSignature = location.signature.adding(typeID)
                moveEntity(entityID, from: location, to: newSignature, addingComponent: component)
            } else {
                // Update existing component
                archetype.setComponent(component, at: location.index)
            }
        }, events: {
            if isNewComponent {
                // Notify observers of addition
                mutations.added(entity: Entity(id: entityID, world: self), component: component)
            } else {
                // Notify observers of change
                mutations.changed(entity: Entity(id: entityID, world: self), component: component)
            }
        })
    }

    internal func component<T: Component>(_ type: T.Type, for entityID: EntityID) -> T? {
        trackStorageAccess()
        guard let location = entityLocations[entityID],
              let archetype = archetypes[location.signature] else { return nil }
        return archetype.getComponent(type, at: location.index)
    }

    /// Get all components for an entity.
    public func allComponents(for entityID: EntityID) -> [any Component] {
        trackStorageAccess()
        guard let location = entityLocations[entityID],
              let archetype = archetypes[location.signature] else { return [] }
        return archetype.allComponents(at: location.index)
    }

    @discardableResult
    internal func removeComponent<T: Component>(_ type: T.Type, from entityID: EntityID) -> T? {
        guard let location = entityLocations[entityID] else { return nil }
        let typeID = ComponentType(T.self)

        guard location.signature.contains(typeID) else { return nil }
        guard let value = archetypes[location.signature]?.getComponent(type, at: location.index) else {
            return nil
        }
        mutations.perform({
            let newSignature = location.signature.removing(typeID)
            moveEntity(entityID, from: location, to: newSignature, removingType: typeID)
        }, events: {
            // Notify observers of removal
            mutations.removed(entity: Entity(id: entityID, world: self), component: value)
        })

        return value
    }

    internal func hasComponent<T: Component>(_ type: T.Type, for entityID: EntityID) -> Bool {
        trackStorageAccess()
        guard let location = entityLocations[entityID] else { return false }
        return location.signature.contains(ComponentType(type))
    }

    // MARK: - Archetype Management (Private)

    private func getOrCreateArchetype(_ signature: ArchetypeSignature) -> Archetype {
        if let existing = archetypes[signature] {
            return existing
        }
        let archetype = Archetype(signature: signature)
        archetypes[signature] = archetype

        // Invalidate all registered query caches when a new archetype is created
        queries.invalidateArchetypes()

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
        structuralRevision &+= 1
    }

    private func moveEntity(
        _ entityID: EntityID,
        from oldLocation: EntityLocation,
        to newSignature: ArchetypeSignature,
        removingType: ComponentType
    ) {
        guard let oldArchetype = archetypes[oldLocation.signature] else { return }
        let newArchetype = getOrCreateArchetype(newSignature)

        let newIndex = newArchetype.addEntity(entityID)
        oldArchetype.copyComponents(at: oldLocation.index, to: newArchetype, targetIndex: newIndex, excludeType: removingType)

        if let movedEntity = oldArchetype.removeEntity(at: oldLocation.index) {
            entityLocations[movedEntity]?.index = oldLocation.index
        }

        entityLocations[entityID] = EntityLocation(signature: newSignature, index: newIndex)
        structuralRevision &+= 1
    }

    // MARK: - System Management

    /// Update all systems in dependency order.
    /// - Throws: `SystemError` if dependencies cannot be resolved.
    public func update(deltaTime: Double) throws {
        try execute(defaultPipeline, deltaTime: deltaTime, advancesTime: true)
    }

    internal func execute(_ pipeline: Pipeline, deltaTime: Double, advancesTime: Bool) throws {
        let schedule = try resolve(pipeline)
        try mutations.batch {
            pipelineExecutionDepth += 1
            defer {
                pipelineExecutionDepth -= 1
                if pipelineExecutionDepth == 0 {
                    let cleanup = pendingSystemCleanup
                    pendingSystemCleanup.removeAll()
                    for system in cleanup {
                        system.cleanup()
                    }
                }
            }
            // Advance time BEFORE systems run, so simulationTime represents "now"
            if advancesTime {
                simulationTime += deltaTime
            }
            for descriptor in schedule {
                try descriptor.implementation?.execute(self, deltaTime)
            }
        }
    }

    /// Get the current system execution order.
    public var systemExecutionOrder: [SystemID] {
        get throws {
            try executionOrder(for: defaultPipeline)
        }
    }
}
