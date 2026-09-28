internal final class PipelineExecution {
    var statistics = PipelineRunStatistics()
    private var commands: [(World) throws -> Void] = []
    private var effects = CommandEffects()
    private var reservedIDs: Set<EntityID> = []
    private var nextCommand = 0
    private var isFlushing = false
    private var failure: (any Error)?

    func run(_ systems: [System], in world: World, deltaTime: Double, synchronization: PipelineSynchronization) throws {
        do {
            for system in systems {
                if requiresMerge(before: system.access, hasObservers: world.mutations.hasObservers) {
                    try flush(in: world)
                }
                statistics.systemCount += 1
                append(try system.execute(world, deltaTime))
                if synchronization == .afterEachSystem || world.mutations.hasObservers || system.access.commandEffects.requiresBarrier {
                    try flush(in: world)
                }
            }
            try flush(in: world)
        } catch {
            // Earlier successful callbacks retain their effects even if a later callback fails.
            try flush(in: world)
            throw error
        }
    }

    private func requiresMerge(before access: SystemAccess, hasObservers: Bool) -> Bool {
        nextCommand < commands.count && (hasObservers || effects.requiresMerge(before: access))
    }

    private func append(_ batch: SystemCommandBatch) {
        guard !batch.commands.isEmpty else {
            return
        }
        commands.append(contentsOf: batch.commands)
        effects.merge(batch.effects)
        reservedIDs.formUnion(batch.reservedIDs)
    }

    func flush(in world: World) throws {
        if let failure {
            throw failure
        }
        guard nextCommand < commands.count else {
            return
        }
        let ownsFlush = !isFlushing
        if ownsFlush {
            statistics.mergeCount += 1
            isFlushing = true
        }
        defer {
            if ownsFlush {
                isFlushing = false
                discard(in: world)
            }
        }
        while nextCommand < commands.count {
            let command = commands[nextCommand]
            // A reentrant run drains the remaining commands, never this command again.
            nextCommand += 1
            statistics.commandCount += 1
            do {
                try command(world)
            } catch {
                failure = error
                nextCommand = commands.count
                throw error
            }
            if let failure {
                throw failure
            }
        }
    }

    func discard(in world: World) {
        world.reservedCommandIDs.subtract(reservedIDs)
        reservedIDs.removeAll()
        commands.removeAll()
        effects = CommandEffects()
        nextCommand = 0
        failure = nil
    }
}
