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
    internal var executions: [PipelineExecution] = []
    @ObservationIgnored
    internal var parallelRunActive = false
    @ObservationIgnored
    internal var reservedCommandIDs: Set<EntityID> = []
    @ObservationIgnored
    public internal(set) var lastRunStatistics = PipelineRunStatistics()
    @ObservationIgnored
    internal var archetypes: [ArchetypeSignature: Archetype] = [:]
    @ObservationIgnored
    @usableFromInline internal let revisionCell = OwnerCell<UInt64>(0)

    // Changes whenever an entity is created, destroyed, or gains or loses a component type, so a cached
    // ComponentRef may point at the wrong row. Value writes do not change it.
    @inlinable public internal(set) var structuralRevision: UInt64 {
        get { revisionCell.value }
        set { revisionCell.value = newValue }
    }
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
    internal let relationshipGraph = RelationshipGraph()

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
        archetypes[emptySignature] = Archetype(signature: emptySignature, serial: 0)
    }

    @ObservationIgnored
    private var lastArchetypeSerial: UInt64 = 0

    // MARK: - Entity Management

    /// Create an entity with no components.
    @discardableResult
    public func createEntity() -> Entity {
        let id = generateUniqueEntityID()
        mutations.perform {
            let archetype = archetypes[emptySignature]!
            let index = archetype.addEntity(id)
            entityLocations[id] = EntityLocation(signature: emptySignature, archetypeSerial: archetype.serial, index: index)
            structuralRevision &+= 1
        }
        return Entity(id: id, world: self)
    }

    /// Create an entity with components.
    @discardableResult
    public func createEntity<each T: Component>(_ components: repeat each T) -> Entity {
        createEntity(id: generateUniqueEntityID(), repeat each components)
    }

    // Traps if `id` is already in use.
    @discardableResult
    public func createEntity<each T: Component>(id: EntityID, _ components: repeat each T) -> Entity {
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
            entityLocations[id] = EntityLocation(signature: signature, archetypeSerial: archetype.serial, index: index)
            structuralRevision &+= 1
        }
        return Entity(id: id, world: self)
    }

    // For callers that only know their components at run time. Traps if `id` is in use or a type repeats.
    @discardableResult
    public func createEntity(id: EntityID, components: [any Component]) -> Entity {
        precondition(entityLocations[id] == nil, "Entity ID already exists")
        let signature = ArchetypeSignature(Set(components.map { Self.componentType(of: $0) }))
        precondition(signature.types.count == components.count, "Component types must be unique")
        mutations.perform {
            let archetype = getOrCreateArchetype(signature)
            let index = archetype.addEntity(id)
            for component in components {
                archetype.setComponent(component, at: index)
            }
            entityLocations[id] = EntityLocation(signature: signature, archetypeSerial: archetype.serial, index: index)
            structuralRevision &+= 1
        }
        return Entity(id: id, world: self)
    }

    private static func componentType<T: Component>(of _: T) -> ComponentType {
        ComponentType(T.self)
    }

    /// Remove an entity.
    @discardableResult
    internal func removeEntity(_ id: EntityID) -> Bool {
        guard let location = entityLocations[id], let archetype = archetypes[location.signature] else {
            return false
        }
        let implementation = component(SystemDescriptor.self, for: id)?.implementation
        mutations.perform({
            entityLocations.removeValue(forKey: id)
            structuralRevision &+= 1
            relationshipGraph.removeEntity(id)
            if let movedEntity = archetype.removeEntity(at: location.index) {
                entityLocations[movedEntity]?.index = location.index
            }
            reclaimIfEmpty(archetype)
        }, events: {
            if mutations.hasDestroyObservers {
                mutations.destroyed(id)
            }
        })
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
            entityLocations[newID] = EntityLocation(
                signature: location.signature, archetypeSerial: targetArchetype.serial, index: newIndex
            )
            structuralRevision &+= 1
            relationshipGraph.copyOutgoing(from: id, to: newID)
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

    /// Register an observer that runs after an entity is destroyed. Component observers get no events for the
    /// destroyed entity's components.
    @discardableResult
    public func observeDestroyed(_ handler: @escaping (EntityID) -> Void) -> ObservationToken {
        mutations.observeDestroyed(handler)
    }

    /// Register an observer for edges of one relationship type being added or removed.
    @discardableResult
    public func observeRelationship<R: Relationship>(
        _ type: R.Type,
        handler: @escaping (RelationshipEvent) -> Void
    ) -> ObservationToken {
        mutations.observeRelationship(RelationshipType(type), handler: handler)
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

    @usableFromInline
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

    @usableFromInline
    internal func component<T: Component>(_ type: T.Type, for entityID: EntityID) -> T? {
        trackStorageAccess()
        guard let location = entityLocations[entityID],
              let archetype = archetypes[location.signature] else { return nil }
        return archetype.getComponent(type, at: location.index)
    }

    // Where an entity's components are stored. While it is unchanged, ComponentRefs made for the entity stay valid,
    // even if `structuralRevision` changed because of other entities. Nil if the entity does not exist.
    public struct StorageLocation: Equatable, Sendable {
        let archetypeSerial: UInt64
        let index: Int
    }

    public func storageLocation(of entityID: EntityID) -> StorageLocation? {
        mutations.checkAccessible()
        guard let location = entityLocations[entityID] else {
            return nil
        }
        return StorageLocation(archetypeSerial: location.archetypeSerial, index: location.index)
    }

    // Valid until `structuralRevision` changes. Finding the ref is not observed; reading `value` is.
    public func componentRef<T: Component>(_ type: T.Type, for entityID: EntityID) -> ComponentRef<T>? {
        mutations.checkAccessible()
        guard let location = entityLocations[entityID],
              let column = archetypes[location.signature]?.column(for: type) else { return nil }
        return ComponentRef(world: self, entityID: entityID, column: column, index: location.index)
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

    @usableFromInline
    internal func matchesSystemRow(_ id: EntityID, requiring types: Set<ComponentType>) -> Bool {
        trackStorageAccess()
        return entityLocations[id]?.signature.isSuperset(of: types) == true
    }

    @usableFromInline
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
        lastArchetypeSerial += 1
        let archetype = Archetype(signature: signature, serial: lastArchetypeSerial)
        archetypes[signature] = archetype

        // Invalidate all registered query caches when a new archetype is created
        queries.invalidateArchetypes()

        return archetype
    }

    // Drop an archetype once its last entity leaves. The base empty-signature
    // archetype is kept because it is the reusable home for component-less
    // entities. Removal is result-invariant (an empty archetype matches nothing)
    // and bumps the query generation so cached selections rebuild without it.
    // Lazy sequences, snapshots, and typed references hold the archetype class
    // directly, so a concurrent iteration keeps its own reference alive.
    private func reclaimIfEmpty(_ archetype: Archetype) {
        guard archetype.signature != emptySignature, archetype.entities.isEmpty else {
            return
        }
        archetypes.removeValue(forKey: archetype.signature)
        queries.invalidateArchetypes()
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

        entityLocations[entityID] = EntityLocation(signature: newSignature, archetypeSerial: newArchetype.serial, index: newIndex)
        structuralRevision &+= 1
        reclaimIfEmpty(oldArchetype)
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

        entityLocations[entityID] = EntityLocation(signature: newSignature, archetypeSerial: newArchetype.serial, index: newIndex)
        structuralRevision &+= 1
        reclaimIfEmpty(oldArchetype)
    }

    // MARK: - System Management

    /// Update all systems in dependency order.
    /// - Throws: `SystemError` if dependencies cannot be resolved.
    public func update(deltaTime: Double) throws {
        try execute(defaultPipeline, deltaTime: deltaTime, advancesTime: true)
    }

    internal func execute(_ pipeline: Pipeline, deltaTime: Double, advancesTime: Bool) throws {
        try synchronizeBeforeRun()
        let schedule = try resolve(pipeline)
        try executeSystems(schedule.compactMap(\.implementation), deltaTime: deltaTime, advancesTime: advancesTime, synchronization: pipeline.synchronization)
    }

    internal func synchronizeBeforeRun() throws {
        guard !parallelRunActive else {
            throw SystemError.parallelRunInProgress
        }
        for execution in executions {
            try execution.flush(in: self)
        }
    }

    internal func executeSystems(_ systems: [System], deltaTime: Double, advancesTime: Bool, synchronization: PipelineSynchronization) throws {
        let execution = PipelineExecution()
        try mutations.batch {
            pipelineExecutionDepth += 1
            executions.append(execution)
            defer {
                execution.discard(in: self)
                executions.removeLast()
                pipelineExecutionDepth -= 1
                if pipelineExecutionDepth == 0 {
                    let cleanup = pendingSystemCleanup
                    pendingSystemCleanup.removeAll()
                    for system in cleanup {
                        system.cleanup()
                    }
                }
                lastRunStatistics = execution.statistics
            }
            // Advance time BEFORE systems run, so simulationTime represents "now"
            if advancesTime {
                simulationTime += deltaTime
            }
            try execution.run(systems, in: self, deltaTime: deltaTime, synchronization: synchronization, cancellationChecks: false)
        }
    }

    internal func beginParallelRun(_ execution: PipelineExecution, deltaTime: Double, advancesTime: Bool) {
        mutations.beginBatch()
        parallelRunActive = true
        pipelineExecutionDepth += 1
        executions.append(execution)
        if advancesTime {
            simulationTime += deltaTime
        }
    }

    internal func endParallelRun(_ execution: PipelineExecution) {
        mutations.isParallelSuspended = false
        execution.discard(in: self)
        executions.removeLast()
        pipelineExecutionDepth -= 1
        let cleanup = pendingSystemCleanup
        pendingSystemCleanup.removeAll()
        for system in cleanup {
            system.cleanup()
        }
        lastRunStatistics = execution.statistics
        mutations.endBatch()
        parallelRunActive = false
    }

    /// Get the current system execution order.
    public var systemExecutionOrder: [SystemID] {
        get throws {
            try executionOrder(for: defaultPipeline)
        }
    }
}
