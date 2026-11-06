extension World {
    /// Returns the entity for the system ID, including unresolved forward references.
    public func systemEntity(for id: SystemID) -> Entity? {
        snapshot(with: SystemDescriptor.self).first { $0[SystemDescriptor.self]?.id == id }
    }

    /// Creates a phase that runs after the given phases.
    ///
    /// - Throws: ``SystemError/invalidPhase(_:)`` if a predecessor is not a phase.
    @discardableResult
    public func createPhase(_ name: String, after predecessors: [Entity] = []) throws -> Entity {
        for predecessor in predecessors {
            try validatePhase(predecessor)
        }
        return try mutations.batch {
            let phase = createEntity(Phase(name))
            for predecessor in predecessors {
                try phase.addRelationship(DependsOn.self, to: predecessor)
            }
            return phase
        }
    }

    /// Registers a system and calls its initialize hook.
    ///
    /// `dependencies`, `before`, and `after` can name systems that are not registered yet.
    ///
    /// - Parameters:
    ///   - system: The system to register.
    ///   - id: The registration ID. Defaults to the system's ID.
    ///   - dependencies: Systems that must run first. Same as `after`.
    ///   - phase: The phase to run in. Defaults to a lazily created phase named `Update`.
    ///   - before: Systems that must run after this one.
    ///   - after: Systems that must run before this one.
    /// - Returns: The system entity.
    /// - Throws: ``SystemError`` if the ID is taken, the phase is invalid, or an input is invalid.
    @discardableResult
    public func addSystem(_ system: System, id: SystemID? = nil, dependencies: [SystemID] = [], phase: Entity? = nil, before: [SystemID] = [], after: [SystemID] = []) throws -> Entity {
        try system.validate()
        let systemID = id ?? system.id
        if systemEntity(for: systemID)?[SystemDescriptor.self]?.isRegistered == true {
            throw SystemError.duplicateID(systemID)
        }
        if let phase {
            try validatePhase(phase)
        }
        return try mutations.batch {
            let entity = reference(to: systemID)
            let selectedPhase: Entity
            if let phase {
                selectedPhase = phase
            } else {
                selectedPhase = defaultPhase()
            }
            try entity.addRelationship(InPhase.self, to: selectedPhase)
            for dependency in dependencies + after {
                try entity.addRelationship(DependsOn.self, to: reference(to: dependency))
            }
            for successor in before {
                try reference(to: successor).addRelationship(DependsOn.self, to: entity)
            }
            let order = nextSystemRegistrationOrder
            nextSystemRegistrationOrder += 1
            entity.set(SystemDescriptor(id: systemID, implementation: system, registrationOrder: order))
            system.initialize()
            return entity
        }
    }

    /// Removes every system and unresolved system reference. Phases and pipelines remain.
    public func removeAllSystems() {
        mutations.batch {
            let entities = snapshot(with: SystemDescriptor.self)
                .sorted { ($0[SystemDescriptor.self]?.registrationOrder ?? 0) < ($1[SystemDescriptor.self]?.registrationOrder ?? 0) }
            for entity in entities {
                removeEntity(entity.id)
            }
        }
    }

    /// Runs one system without registering it or calling its lifecycle hooks. Does not advance simulation time.
    public func run(_ system: System, deltaTime: Double) throws {
        try synchronizeBeforeRun()
        try system.validate()
        try executeSystems([system], deltaTime: deltaTime, advancesTime: false, synchronization: .automatic)
    }

    /// Runs the systems the pipeline selects. Does not advance simulation time.
    ///
    /// - Throws: ``SystemError`` for an invalid schedule, or an error from a system callback.
    public func run(_ pipeline: Pipeline, deltaTime: Double) throws {
        try execute(pipeline, deltaTime: deltaTime, advancesTime: false)
    }

    /// Runs the pipeline stored on the entity. Does not advance simulation time.
    ///
    /// - Throws: ``SystemError/invalidPipeline(_:)`` if the entity has no ``Pipeline``.
    public func run(_ pipeline: Entity, deltaTime: Double) throws {
        try synchronizeBeforeRun()
        try validateRelationshipEntity(pipeline)
        guard let configuration = pipeline[Pipeline.self] else {
            throw SystemError.invalidPipeline(pipeline.id)
        }
        try run(configuration, deltaTime: deltaTime)
    }

    /// Returns the order in which the pipeline runs its systems.
    ///
    /// - Throws: ``SystemError`` if the schedule is invalid.
    public func executionOrder(for pipeline: Pipeline) throws -> [SystemID] {
        try resolve(pipeline).map(\.id)
    }

    internal func resolve(_ pipeline: Pipeline) throws -> [SystemDescriptor] {
        try resolveSchedule(pipeline).map(\.descriptor)
    }

    internal func resolveSchedule(_ pipeline: Pipeline) throws -> [ScheduledSystem] {
        let selected = snapshot(matching: pipeline.query.with(SystemDescriptor.self))
            .filter { $0[SystemDescriptor.self]?.isRegistered == true }
            .sorted { ($0[SystemDescriptor.self]?.registrationOrder ?? 0) < ($1[SystemDescriptor.self]?.registrationOrder ?? 0) }
        let selectedIDs = Set(selected.map(\.id))
        var dependencies: [EntityID: Set<EntityID>] = [:]
        var phaseMembers: [EntityID: Set<EntityID>] = [:]
        var phases: [(entityID: EntityID, phase: Entity)] = []
        for (entity, descriptor) in selected.compactMap({ entity in entity[SystemDescriptor.self].map { (entity, $0) } }) {
            let memberships = entity.targets(of: InPhase.self)
            guard let phase = memberships.first, memberships.count == 1 else {
                throw SystemError.missingPhase(descriptor.id)
            }
            try validatePhase(phase)
            phases.append((entity.id, phase))
            phaseMembers[phase.id, default: []].insert(entity.id)
            dependencies[entity.id] = []
            for target in entity.targets(of: DependsOn.self) {
                guard let predecessor = target[SystemDescriptor.self] else {
                    throw SystemError.invalidDependency(source: entity.id, target: target.id)
                }
                guard predecessor.isRegistered else {
                    throw SystemError.dependencyNotFound(system: descriptor.id, dependency: predecessor.id)
                }
                guard selectedIDs.contains(target.id) else {
                    throw SystemError.excludedDependency(system: descriptor.id, dependency: predecessor.id)
                }
                dependencies[entity.id, default: []].insert(target.id)
            }
        }

        var visited: Set<EntityID> = []
        var active: Set<EntityID> = []
        var ancestors: [EntityID: Set<EntityID>] = [:]
        for (entityID, phase) in phases {
            for predecessor in try phaseAncestors(of: phase, visited: &visited, active: &active, ancestors: &ancestors) {
                dependencies[entityID, default: []].formUnion(phaseMembers[predecessor] ?? [])
            }
        }

        return try orderedSystems(selected, dependencies: dependencies)
    }

    private func phaseAncestors(of phase: Entity, visited: inout Set<EntityID>, active: inout Set<EntityID>, ancestors: inout [EntityID: Set<EntityID>]) throws -> Set<EntityID> {
        if active.contains(phase.id) {
            throw SystemError.phaseCycle(phase.id)
        }
        if visited.contains(phase.id) {
            return ancestors[phase.id] ?? []
        }
        try validatePhase(phase)
        active.insert(phase.id)
        var predecessors: Set<EntityID> = []
        for target in phase.targets(of: DependsOn.self) {
            predecessors.insert(target.id)
            predecessors.formUnion(try phaseAncestors(of: target, visited: &visited, active: &active, ancestors: &ancestors))
        }
        active.remove(phase.id)
        visited.insert(phase.id)
        ancestors[phase.id] = predecessors
        return predecessors
    }

    private func orderedSystems(_ selected: [Entity], dependencies originalDependencies: [EntityID: Set<EntityID>]) throws -> [ScheduledSystem] {
        var dependencies = originalDependencies
        var remaining = selected
        var result: [ScheduledSystem] = []
        while !remaining.isEmpty {
            guard let index = remaining.firstIndex(where: { dependencies[$0.id, default: []].isEmpty }) else {
                throw SystemError.cyclicDependency(remaining.compactMap { $0[SystemDescriptor.self]?.id })
            }
            let entity = remaining.remove(at: index)
            if let descriptor = entity[SystemDescriptor.self] {
                result.append(ScheduledSystem(entityID: entity.id, descriptor: descriptor, predecessors: originalDependencies[entity.id, default: []]))
            }
            for dependent in remaining {
                dependencies[dependent.id]?.remove(entity.id)
            }
        }
        return result
    }

    private func reference(to id: SystemID) -> Entity {
        if let existing = systemEntity(for: id) {
            return existing
        }
        return createEntity(SystemDescriptor(id: id, implementation: nil, registrationOrder: 0))
    }

    private func defaultPhase() -> Entity {
        if let existing = snapshot(with: DefaultPhase.self).first, existing.contains(Phase.self) {
            return existing
        }
        return createEntity(Phase("Update"), DefaultPhase())
    }

    private func validatePhase(_ entity: Entity) throws {
        try validateRelationshipEntity(entity)
        guard entity.contains(Phase.self) else {
            throw SystemError.invalidPhase(entity.id)
        }
    }
}

private struct DefaultPhase: Component {}
