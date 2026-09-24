import Collections
import Observation

/// Metadata for a registered system.
struct SystemEntry {
    let system: System
    let dependencies: [SystemID]
}

/// Container for entities, components, and systems.
@Observable
public final class World {
    @ObservationIgnored
    internal var systems: OrderedDictionary<SystemID, SystemEntry> = [:]
    @ObservationIgnored
    internal var systemOrder: [SystemID] = []  // Topologically sorted system IDs
    @ObservationIgnored
    private var systemOrderDirty: Bool = false
    @ObservationIgnored
    internal var archetypes: [ArchetypeSignature: Archetype] = [:]
    @ObservationIgnored
    internal var entityLocations: [EntityID: EntityLocation] = [:]
    @ObservationIgnored
    private let emptySignature = ArchetypeSignature()
    @ObservationIgnored
    private let observers = ObserverRegistry()

    private var storageRevision: UInt64 = 0
    @ObservationIgnored private var updateDepth = 0
    @ObservationIgnored private var storageIsDirty = false

    @usableFromInline
    internal func trackStorageAccess() {
        _ = storageRevision
    }

    @usableFromInline
    internal func storageDidChange() {
        if updateDepth > 0 {
            storageIsDirty = true
        } else {
            storageRevision &+= 1
        }
    }

    private func finishStorageUpdate() {
        updateDepth -= 1
        guard updateDepth == 0, storageIsDirty else {
            return
        }
        storageIsDirty = false
        storageRevision &+= 1
    }

    @ObservationIgnored
    internal var relationships: [RelationshipType: RelationshipStorage] = [:]

    internal func removeEntities<S: Sequence>(_ ids: S) -> Int where S.Element == EntityID {
        updateDepth += 1
        defer { finishStorageUpdate() }
        var removed = 0
        for id in ids where removeEntity(id) {
            removed += 1
        }
        return removed
    }

    // Registered query support
    @ObservationIgnored
    internal var registeredQueries: [Query: RegisteredQueryCache] = [:]

    /// The current simulation time (accumulated deltaTime from all updates).
    /// This is observable and updates once per `update()` call.
    public private(set) var simulationTime: Double = 0.0

    /// Create an empty world.
    public init() {
        archetypes[emptySignature] = Archetype(signature: emptySignature)
    }

    // MARK: - Entity Management

    /// Create an entity with no components.
    @discardableResult
    public func createEntity() -> Entity {
        defer { storageDidChange() }
        let id = generateUniqueEntityID()

        let archetype = archetypes[emptySignature]!
        let index = archetype.addEntity(id)
        entityLocations[id] = EntityLocation(signature: emptySignature, index: index)

        return Entity(id: id, world: self)
    }

    /// Create an entity with components.
    @discardableResult
    public func createEntity<each T: Component>(_ components: repeat each T) -> Entity {
        defer { storageDidChange() }
        let id = generateUniqueEntityID()

        var typeIDs = Set<ComponentType>()
        for typeID in repeat ComponentType((each T).self) {
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

        defer { storageDidChange() }
        for storage in relationships.values {
            storage.removeEntity(id)
        }
        if let movedEntity = archetype.removeEntity(at: location.index) {
            entityLocations[movedEntity]?.index = location.index
        }

        return true
    }

    /// Clone an entity, creating a new entity with copies of all components.
    @discardableResult
    internal func cloneEntity(_ id: EntityID) -> Entity? {
        guard let location = entityLocations[id],
              let sourceArchetype = archetypes[location.signature] else { return nil }

        defer { storageDidChange() }
        let newID = generateUniqueEntityID()
        let targetArchetype = getOrCreateArchetype(location.signature)

        let newIndex = targetArchetype.addEntity(newID)
        sourceArchetype.copyComponents(at: location.index, to: targetArchetype, targetIndex: newIndex)
        entityLocations[newID] = EntityLocation(signature: location.signature, index: newIndex)
        for storage in relationships.values {
            for target in storage.targets(from: id) {
                storage.insert(source: newID, target: target)
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
        observers.observe(type, handler: handler)
    }

    /// Unregister an observer.
    public func removeObserver(_ token: ObservationToken) {
        observers.removeObserver(token)
    }

    /// Notify observers of a component change.
    @usableFromInline
    internal func notifyChanged<T: Component>(entityID: EntityID, component: T) {
        observers.notifyChanged(entity: Entity(id: entityID, world: self), component: component)
    }

    // MARK: - Component Access (Internal)

    internal func addComponent<T: Component>(_ component: T, to entityID: EntityID) {
        guard let location = entityLocations[entityID] else { return }
        defer { storageDidChange() }
        let typeID = ComponentType(T.self)

        let isNewComponent = !location.signature.contains(typeID)

        if !isNewComponent {
            // Update existing component
            if let archetype = archetypes[location.signature] {
                archetype.setComponent(component, at: location.index)
            }
            // Notify observers of change
            observers.notifyChanged(entity: Entity(id: entityID, world: self), component: component)
            return
        }

        let newSignature = location.signature.adding(typeID)
        moveEntity(entityID, from: location, to: newSignature, addingComponent: component)

        // Notify observers of addition
        observers.notifyAdded(entity: Entity(id: entityID, world: self), component: component)
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
        defer { storageDidChange() }

        let value = archetypes[location.signature]?.getComponent(type, at: location.index)

        let newSignature = location.signature.removing(typeID)
        moveEntity(entityID, from: location, to: newSignature, removingType: typeID)

        // Notify observers of removal
        if let value {
            observers.notifyRemoved(entity: Entity(id: entityID, world: self), component: value)
        }

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
        invalidateRegisteredQueryCaches()

        return archetype
    }

    private func invalidateRegisteredQueryCaches() {
        for (_, cache) in registeredQueries {
            cache.isDirty = true
        }
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
    }

    // MARK: - System Management

    /// Add a system with an optional ID and dependencies.
    /// - Parameters:
    ///   - system: The system to add.
    ///   - id: Optional ID for the system. Defaults to the type name.
    ///   - dependencies: IDs of systems that must run before this one.
    /// - Throws: `SystemError.duplicateID` if a system with this ID already exists.
    public func addSystem(
        _ system: System,
        id: SystemID? = nil,
        dependencies: [SystemID] = []
    ) throws {
        let systemID = id ?? SystemID(String(describing: type(of: system)))

        if systems[systemID] != nil {
            throw SystemError.duplicateID(systemID)
        }

        let entry = SystemEntry(system: system, dependencies: dependencies)
        systems[systemID] = entry
        systemOrderDirty = true

        system.initialize(world: self)
    }

    /// Remove all systems.
    public func removeAllSystems() {
        for (_, entry) in systems {
            entry.system.cleanup(world: self)
        }
        systems.removeAll()
        systemOrder.removeAll()
        systemOrderDirty = false
    }

    /// Update all systems in dependency order.
    /// - Throws: `SystemError` if dependencies cannot be resolved.
    public func update(deltaTime: Double) throws {
        updateDepth += 1
        defer { finishStorageUpdate() }
        if systemOrderDirty {
            try rebuildSystemOrder()
        }

        // Advance time BEFORE systems run, so simulationTime represents "now"
        simulationTime += deltaTime

        for systemID in systemOrder {
            systems[systemID]!.system.update(world: self, deltaTime: deltaTime)
        }
    }

    /// Rebuild the system execution order using topological sort.
    private func rebuildSystemOrder() throws {
        let systemIDs = Array(systems.keys)
        let idToIndex = Dictionary(uniqueKeysWithValues: systemIDs.enumerated().map { ($1, $0) })

        // Build adjacency list and in-degree count
        var inDegree = [Int](repeating: 0, count: systems.count)
        var dependents: [[Int]] = Array(repeating: [], count: systems.count)

        for (index, systemID) in systemIDs.enumerated() {
            let entry = systems[systemID]!
            for dep in entry.dependencies {
                guard let depIndex = idToIndex[dep] else {
                    throw SystemError.dependencyNotFound(system: systemID, dependency: dep)
                }
                dependents[depIndex].append(index)
                inDegree[index] += 1
            }
        }

        // Kahn's algorithm for topological sort
        var queue: [Int] = []
        for (index, degree) in inDegree.enumerated() where degree == 0 {
            queue.append(index)
        }

        var sorted: [Int] = []
        var queueIndex = 0

        while queueIndex < queue.count {
            let current = queue[queueIndex]
            queueIndex += 1
            sorted.append(current)

            for dependent in dependents[current] {
                inDegree[dependent] -= 1
                if inDegree[dependent] == 0 {
                    queue.append(dependent)
                }
            }
        }

        // Check for cycle
        if sorted.count != systems.count {
            // Find systems involved in cycle
            let cycleIndices = inDegree.enumerated().filter { $0.element > 0 }.map(\.offset)
            let cycleIDs = cycleIndices.map { systemIDs[$0] }
            throw SystemError.cyclicDependency(cycleIDs)
        }

        systemOrder = sorted.map { systemIDs[$0] }
        systemOrderDirty = false
    }

    /// Get the current system execution order.
    public var systemExecutionOrder: [SystemID] {
        if systemOrderDirty {
            try? rebuildSystemOrder()
        }
        return systemOrder
    }
}
