import Foundation
@testable import SwiftECS
import Testing

private actor JobBarrier {
    let width: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var arrivals = 0
    private var active = 0
    private(set) var peak = 0

    init(width: Int) { self.width = width }

    func enter() async {
        active += 1
        peak = max(peak, active)
        arrivals += 1
        if arrivals == width {
            arrivals = 0
            let continuations = waiting
            waiting.removeAll()
            for continuation in continuations { continuation.resume() }
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    func leave() { active -= 1 }
}

@Test(arguments: [1, 2, 4])
func `structured execution overlaps jobs without exceeding its bound`(limit: Int) async {
    let barrier = JobBarrier(width: limit)
    let jobs = (0..<8).map { _ in
        ParallelJob {
            await barrier.enter()
            await barrier.leave()
            return ParallelJobResult(commands: [], reservedIDs: [], didWrite: false, error: nil)
        }
    }
    let results = await ParallelExecutor.run(jobs, limit: limit)
    #expect(results.count == 8)
    #expect(await barrier.peak == limit)
}

@MainActor @Test func `independent pipeline systems enter the executor together`() async throws {
    let world = World()
    let barrier = JobBarrier(width: 2)
    for name in ["first", "second"] {
        var system = System(SystemID(name))
        system.prepareParallel = { _, _, _, _ in
            let job = ParallelJob {
                await barrier.enter()
                await barrier.leave()
                return ParallelJobResult(commands: [], reservedIDs: [], didWrite: false, error: nil)
            }
            return [job]
        }
        try world.addSystem(system)
    }
    try await world.update(deltaTime: 0, parallelism: 2)
    #expect(await barrier.peak == 2)
    #expect(world.lastRunStatistics.parallelBatchCount == 1)
}

private actor ReleaseGate {
    private var open = false
    private var waiting: CheckedContinuation<Void, Never>?

    func wait() async {
        if !open {
            await withCheckedContinuation { waiting = $0 }
        }
    }

    func release() {
        open = true
        waiting?.resume()
        waiting = nil
    }
}

@MainActor private final class ParallelTestOwner {
    let world = World()
    var system = System("test")

    func run() async throws {
        try await world.run(system, deltaTime: 0, parallelism: 2)
    }
}

@MainActor @Test func `a suspended parallel run rejects another run on the same world`() async throws {
    let owner = ParallelTestOwner()
    let world = owner.world
    let gate = ReleaseGate()
    let started = AsyncStream<Void>.makeStream()
    var held = System("held")
    held.prepareParallel = { _, _, _, _ in
        let job = ParallelJob {
            started.continuation.yield(())
            await gate.wait()
            return ParallelJobResult(commands: [], reservedIDs: [], didWrite: false, error: nil)
        }
        return [job]
    }
    owner.system = held
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await owner.run() }
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        #expect(world.mutations.isParallelSuspended)
        #expect(throws: SystemError.parallelRunInProgress) { try world.update(deltaTime: 0) }
        await #expect(throws: SystemError.parallelRunInProgress) { try await world.update(deltaTime: 0, parallelism: 2) }
        await gate.release()
        try await group.waitForAll()
    }
    #expect(!world.parallelRunActive)
    #expect(!world.mutations.isParallelSuspended)
    try world.update(deltaTime: 0)
}

// Only the worker blocks; the owning actor releases it through explicit signaling.
private final class CallbackPause: @unchecked Sendable {
    let started = AsyncStream<Void>.makeStream()
    private let condition = NSCondition()
    private var released = false

    func wait() {
        condition.lock()
        started.continuation.yield(())
        while !released { condition.wait() }
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

@MainActor @Test func `cancellation joins an active callback and discards its unfinished commands`() async {
    let owner = ParallelTestOwner()
    let world = owner.world
    let pause = CallbackPause()
    let cancelled = LockedState(false)
    owner.system = System("cancel").runParallel(CreateEntities(ConcurrentHealth.self)) { _, creator in
        try creator.create(ConcurrentHealth(value: 1))
        pause.wait()
    }
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            do {
                try await owner.run()
                Issue.record("Cancelled callback reported success")
            } catch is CancellationError {
                cancelled.withLock { $0 = true }
            } catch {
                Issue.record(error)
            }
        }
        var iterator = pause.started.stream.makeAsyncIterator()
        await iterator.next()
        group.cancelAll()
        pause.release()
        await group.waitForAll()
    }
    #expect(cancelled.withLock { $0 })
    #expect(world.entityCount == 0)
    #expect(world.reservedCommandIDs.isEmpty)
    #expect(!world.parallelRunActive)
    #expect(world.lastRunStatistics.commandCount == 0)
}

private actor SimulationOwner {
    let world: World

    init() throws {
        let world = World()
        world.createEntity(ConcurrentPosition(value: 1))
        try world.addSystem(System("actor").query(Write<ConcurrentPosition>()).eachParallel { _, row in
            row.fields.value.value += 1
        })
        self.world = world
    }

    func step() async throws -> Int {
        try await world.update(deltaTime: 1, parallelism: 2)
        guard let row = world.query(ConcurrentPosition.self).first(where: { _ in true }) else {
            return 0
        }
        let value: ConcurrentPosition = row.values
        return value.value
    }
}

@Test func `a simulation actor retains ownership across parallel execution`() async throws {
    let owner = try SimulationOwner()
    #expect(try await owner.step() == 2)
}

private enum PartitionFailure: Error { case failed }

@MainActor @Test func `one failed partition discards the whole systems command batch`() async throws {
    let world = World()
    for index in 0..<100 { world.createEntity(ConcurrentPosition(value: index)) }
    let system = System("partitions").query(Write<ConcurrentPosition>()).eachParallel(CreateEntities(ConcurrentMarker.self), minimumRowsPerTask: 1) { _, row, creator in
        try creator.create(ConcurrentMarker(source: row.entityID))
        if row.fields.value.value == 13 { throw PartitionFailure.failed }
        row.fields.value.value += 100
    }
    await #expect(throws: PartitionFailure.self) { try await world.run(system, deltaTime: 0, parallelism: 4) }
    #expect(world.snapshot(with: ConcurrentMarker.self).isEmpty)
    #expect(world.query(ConcurrentPosition.self).contains { $0.values.value >= 100 })
    #expect(world.reservedCommandIDs.isEmpty)
    #expect(world.lastRunStatistics.parallelTaskCount == 4)
}

private struct AlternateParallelInput: ParallelSystemInput {
    var binding: SystemBinding<SystemRows<Read<ConcurrentPosition>>> {
        SystemQuery(Read<ConcurrentPosition>()).binding
    }
    var parallelBinding: ParallelBinding<SystemRows<Read<ConcurrentPosition>>> {
        SystemQuery(Read<ConcurrentPosition>(), matching: Query(with: ConcurrentHealth.self)).parallelBinding
    }
}

@MainActor @Test func `parallel preparation and serial fallback use the same sealed declarations`() async throws {
    let world = World()
    world.createEntity(ConcurrentPosition(value: 0))
    let count = LockedState(0)
    let system = System("sealed").runParallel(AlternateParallelInput()) { _, rows in count.withLock { $0 = rows.count { _ in true } } }
    #expect(system.access.queries.first?.components.contains(ComponentType(ConcurrentHealth.self)) == true)
    try world.run(system, deltaTime: 0)
    #expect(count.withLock { $0 } == 0)
    try await world.run(system, deltaTime: 0, parallelism: 2)
    #expect(count.withLock { $0 } == 0)
}
