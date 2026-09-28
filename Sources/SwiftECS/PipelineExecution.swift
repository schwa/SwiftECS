internal final class PipelineExecution {
    var statistics = PipelineRunStatistics()
    private var commands: [(World) throws -> Void] = []
    private var effects = CommandEffects()
    private var reservedIDs: Set<EntityID> = []
    private var nextCommand = 0
    private var isFlushing = false
    private var failure: (any Error)?

    func run(_ systems: [System], in world: World, deltaTime: Double, synchronization: PipelineSynchronization, cancellationChecks: Bool) throws {
        do {
            for system in systems {
                if cancellationChecks {
                    try Task.checkCancellation()
                }
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

    func runParallel(_ schedule: [ScheduledSystem], in world: World, configuration: ParallelRunConfiguration, isolation: isolated (any Actor)?) async throws {
        if configuration.parallelism == 1 {
            try run(schedule.compactMap(\.descriptor.implementation), in: world, deltaTime: configuration.deltaTime, synchronization: configuration.synchronization, cancellationChecks: true)
            try Task.checkCancellation()
            return
        }
        let identities = ParallelIDPool(existing: [])
        var index = 0
        do {
            while index < schedule.count {
                try Task.checkCancellation()
                let wave = parallelWave(schedule, startingAt: index, synchronization: configuration.synchronization, allowed: configuration.parallelism > 1 && !world.mutations.hasObservers)
                if wave.isEmpty {
                    try flush(in: world)
                    if let system = schedule[index].descriptor.implementation {
                        try run([system], in: world, deltaTime: configuration.deltaTime, synchronization: configuration.synchronization, cancellationChecks: true)
                    }
                    index += 1
                    continue
                }
                if wave.contains(where: { requiresMerge(before: $0.descriptor.access ?? SystemAccess(), hasObservers: world.mutations.hasObservers) }) {
                    try flush(in: world)
                    if world.mutations.hasObservers {
                        continue
                    }
                }
                let prepared = prepare(wave, in: world, configuration: configuration, identities: identities)
                try await execute(prepared, in: world, parallelism: configuration.parallelism, isolation: isolation)
                if configuration.synchronization == .afterEachSystem || wave.contains(where: { $0.descriptor.access?.commandEffects.requiresBarrier == true }) {
                    try flush(in: world)
                }
                index += wave.count
            }
            try Task.checkCancellation()
            try flush(in: world)
        } catch {
            world.mutations.isParallelSuspended = false
            try flush(in: world)
            throw error
        }
    }

    private func prepare(_ entries: [ScheduledSystem], in world: World, configuration: ParallelRunConfiguration, identities: ParallelIDPool) -> PreparedParallelWave {
        if entries.contains(where: { $0.descriptor.access?.commandEffects.creationSignatures.isEmpty == false }) {
            identities.include(Set(world.entityLocations.keys).union(world.reservedCommandIDs))
        }
        var wave = PreparedParallelWave(entries: entries)
        for entry in entries {
            let start = wave.jobs.count
            if let prepare = entry.descriptor.implementation?.prepareParallel {
                wave.jobs.append(contentsOf: prepare(world, configuration.deltaTime, identities, configuration.parallelism))
            }
            wave.ranges.append(start..<wave.jobs.count)
            statistics.systemCount += 1
        }
        return wave
    }

    private func execute(_ wave: PreparedParallelWave, in world: World, parallelism: Int, isolation _: isolated (any Actor)?) async throws {
        world.mutations.isParallelSuspended = true
        let results = await ParallelExecutor.run(wave.jobs, limit: parallelism)
        world.mutations.isParallelSuspended = false
        if !wave.jobs.isEmpty {
            statistics.parallelBatchCount += 1
            statistics.parallelTaskCount += wave.jobs.count
        }
        for result in results {
            for update in result.valueUpdates {
                update.apply()
            }
        }
        if results.contains(where: \.didWrite) {
            world.mutations.didChange()
        }
        for (entry, range) in zip(wave.entries, wave.ranges) {
            let outputs = results[range]
            if let error = outputs.compactMap(\.error).first {
                throw error
            }
            var batch = SystemCommandBatch(effects: entry.descriptor.access?.commandEffects ?? CommandEffects())
            for output in outputs {
                batch.commands.append(contentsOf: output.commands.map { command in { try command($0) } })
                batch.reservedIDs.formUnion(output.reservedIDs)
            }
            world.reservedCommandIDs.formUnion(batch.reservedIDs)
            append(batch)
        }
    }

    private func parallelWave(_ schedule: [ScheduledSystem], startingAt start: Int, synchronization: PipelineSynchronization, allowed: Bool) -> [ScheduledSystem] {
        guard allowed else {
            return []
        }
        var wave: [ScheduledSystem] = []
        var identities: Set<EntityID> = []
        for entry in schedule[start...] {
            guard let system = entry.descriptor.implementation, system.isParallelEligible else {
                break
            }
            if !entry.predecessors.isDisjoint(with: identities) || wave.contains(where: { $0.descriptor.access?.conflicts(with: system.access) == true }) {
                break
            }
            if synchronization == .afterEachSystem, !wave.isEmpty {
                break
            }
            wave.append(entry)
            identities.insert(entry.entityID)
        }
        return wave
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
