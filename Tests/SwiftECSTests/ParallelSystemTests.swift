@testable import SwiftECS
import Testing

struct ConcurrentPosition: ConcurrentComponent { var value: Int }
struct ConcurrentVelocity: ConcurrentComponent { var value: Int }
struct ConcurrentHealth: ConcurrentComponent { var value: Int }
struct ConcurrentMarker: ConcurrentComponent { let source: EntityID }
struct ConcurrentExcluded: ConcurrentComponent {}

@MainActor @Test func `independent systems write separate columns of the same entities`() async throws {
    let world = World()
    let entity = world.createEntity(ConcurrentPosition(value: 0), ConcurrentVelocity(value: 0), ConcurrentHealth(value: 3))
    try world.addSystem(System("position").query(Write<ConcurrentPosition>(), Read<ConcurrentHealth>()).runParallel { _, rows in
        for row in rows { row.fields.0.value.value += row.fields.1.value }
    })
    try world.addSystem(System("velocity").query(Write<ConcurrentVelocity>(), Read<ConcurrentHealth>()).runParallel { _, rows in
        for row in rows { row.fields.0.value.value += row.fields.1.value * 2 }
    })
    try await world.update(deltaTime: 1, parallelism: 2)
    #expect(entity[ConcurrentPosition.self]?.value == 3)
    #expect(entity[ConcurrentVelocity.self]?.value == 6)
    #expect(world.lastRunStatistics.parallelBatchCount == 1)
    #expect(world.lastRunStatistics.parallelTaskCount == 2)
    #expect(world.simulationTime == 1)
}

@MainActor @Test func `conflicts explicit dependencies and phases prevent callback overlap`() async throws {
    let world = World()
    let firstPhase = try world.createPhase("first")
    let secondPhase = try world.createPhase("second", after: [firstPhase])
    world.createEntity(ConcurrentPosition(value: 0), ConcurrentHealth(value: 0))
    let log = LockedState<[String]>([])
    let first = System("first").query(Write<ConcurrentPosition>()).runParallel { _, rows in
        for row in rows { row.fields.value.value = 1 }
        log.withLock { $0.append("first") }
    }
    let reader = System("reader").query(Read<ConcurrentPosition>()).runParallel { _, rows in
        #expect(rows.first { _ in true }?.fields.value == 1)
        log.withLock { $0.append("reader") }
    }
    let dependent = System("dependent").runParallel { _ in log.withLock { $0.append("dependent") } }
    try world.addSystem(first, phase: firstPhase)
    try world.addSystem(reader, phase: firstPhase)
    try world.addSystem(dependent, phase: firstPhase, after: [reader.id])
    try world.addSystem(System("laterPhase").runParallel { _ in log.withLock { $0.append("laterPhase") } }, phase: secondPhase)
    try await world.update(deltaTime: 0, parallelism: 4)
    #expect(log.withLock { $0 } == ["first", "reader", "dependent", "laterPhase"])
    #expect(world.lastRunStatistics.parallelBatchCount == 4)
}

@MainActor @Test func `serial callbacks and observers stay on the owning actor`() async throws {
    let world = World()
    let entity = world.createEntity(ConcurrentHealth(value: 0))
    let events = LockedState(0)
    var serialCalls = 0
    var nestedRejected = false
    let token = world.observe(ConcurrentHealth.self) { _ in
        MainActor.assertIsolated()
        events.withLock { $0 += 1 }
        do {
            try world.run(System("nested"), deltaTime: 0)
        } catch SystemError.parallelRunInProgress {
            nestedRejected = true
        } catch {
            Issue.record(error)
        }
    }
    defer { world.removeObserver(token) }
    try world.addSystem(System("parallel").query(Write<ConcurrentHealth>()).eachParallel(minimumRowsPerTask: 1) { _, row in
        row.fields.value.value = 4
        #expect(events.withLock { $0 } == 1)
    })
    try world.addSystem(System("serial").run { _ in
        MainActor.assertIsolated()
        serialCalls += 1
    })
    try await world.update(deltaTime: 0, parallelism: 4)
    #expect(entity[ConcurrentHealth.self]?.value == 4)
    #expect(serialCalls == 1)
    #expect(nestedRejected)
    #expect(world.lastRunStatistics.parallelTaskCount == 0)
}

@MainActor @Test func `parallel entity partitions cover uneven filtered archetypes exactly once`() async throws {
    let world = World()
    var expected: [EntityID] = []
    for index in 0..<307 {
        let entity = world.createEntity(ConcurrentPosition(value: index))
        if index.isMultiple(of: 2) { entity.set(ConcurrentHealth(value: 1)) }
        if index.isMultiple(of: 5) {
            entity.set(ConcurrentExcluded())
        } else {
            expected.append(entity.id)
        }
    }
    let system = System("partitioned").query(Write<ConcurrentPosition>(), matching: Query.all.without(ConcurrentExcluded.self))
        .eachParallel(CreateEntities(ConcurrentMarker.self), minimumRowsPerTask: 7) { _, row, creator in
            row.fields.value.value += 1_000
            try creator.create(ConcurrentMarker(source: row.entityID))
        }
    let order = world.snapshot(matching: Query(with: ConcurrentPosition.self).without(ConcurrentExcluded.self)).map(\.id)
    try await world.run(system, deltaTime: 0, parallelism: 4)
    #expect(world.lastRunStatistics.parallelTaskCount == 4)
    let markers = world.snapshot(with: ConcurrentMarker.self).compactMap { $0[ConcurrentMarker.self]?.source }
    #expect(markers == order)
    #expect(Set(markers) == Set(expected))
    #expect(markers.count == expected.count)
    for entity in world.snapshot(with: ConcurrentPosition.self) {
        let value = try #require(entity[ConcurrentPosition.self]).value
        #expect((value >= 1_000) == !entity.contains(ConcurrentExcluded.self))
    }
}

@MainActor @Test func `parallel command producers reserve distinct identities and merge in logical order`() async throws {
    let world = World()
    let root = world.createEntity().id
    for index in 0..<8 {
        try world.addSystem(System(SystemID("producer-\(index)")).runParallel(CreateEntities(ConcurrentHealth.self)) { _, creator in
            for _ in 0..<20 {
                try creator.create(ConcurrentHealth(value: index))
            }
        })
    }
    try await world.update(deltaTime: 0, parallelism: 3)
    #expect(world.lastRunStatistics.parallelBatchCount == 1)
    #expect(world.lastRunStatistics.parallelTaskCount == 8)
    let linker = System("links").query(Read<ConcurrentHealth>()).eachParallel(EditRelationship<ChildOf>(), minimumRowsPerTask: 10) { _, row, parents in
        parents.add(from: row.entityID, to: root)
    }
    try await world.run(linker, deltaTime: 0, parallelism: 3)
    let children = world.snapshot(with: ConcurrentHealth.self)
    #expect(children.count == 160)
    #expect(Set(children.map(\.id)).count == 160)
    #expect(children.compactMap { $0[ConcurrentHealth.self]?.value } == (0..<8).flatMap { Array(repeating: $0, count: 20) })
    #expect(children.allSatisfy { $0.parent?.id == root })
    #expect(world.reservedCommandIDs.isEmpty)
}

private enum ParallelFailure: Error, Equatable { case first, second }

@MainActor @Test func `parallel failure joins siblings retains writes and discards commands after the failed prefix`() async throws {
    let world = World()
    let entity = world.createEntity(ConcurrentPosition(value: 0), ConcurrentVelocity(value: 0))
    try world.addSystem(System("first").runParallel(SystemQuery(Write<ConcurrentPosition>()), CreateEntities(ConcurrentHealth.self)) { _, rows, creator in
        for row in rows { row.fields.value.value = 1 }
        try creator.create(ConcurrentHealth(value: 1))
        throw ParallelFailure.first
    })
    try world.addSystem(System("second").runParallel(SystemQuery(Write<ConcurrentVelocity>()), CreateEntities(ConcurrentHealth.self)) { _, rows, creator in
        for row in rows { row.fields.value.value = 2 }
        try creator.create(ConcurrentHealth(value: 2))
        throw ParallelFailure.second
    })
    await #expect(throws: ParallelFailure.first) { try await world.update(deltaTime: 0, parallelism: 2) }
    #expect(entity[ConcurrentPosition.self]?.value == 1)
    #expect(entity[ConcurrentVelocity.self]?.value == 2)
    #expect(world.snapshot(with: ConcurrentHealth.self).isEmpty)
    #expect(world.reservedCommandIDs.isEmpty)
    #expect(!world.parallelRunActive)
    #expect(world.lastRunStatistics.parallelTaskCount == 2)
    try world.run(System("recovery"), deltaTime: 0)
}

@MainActor @Test func `parallel validation and empty partitions have no unintended effects`() async throws {
    let world = World()
    await #expect(throws: SystemError.invalidParallelism) { try await world.update(deltaTime: 1, parallelism: 0) }
    let invalid = System("invalid").query(Read<ConcurrentHealth>()).eachParallel(minimumRowsPerTask: 0) { _, _ in }
    #expect(throws: SystemError.invalidPartitionSize) { try world.addSystem(invalid) }
    let empty = System("empty").query(Read<ConcurrentHealth>()).eachParallel { _, _ in Issue.record("Unexpected row") }
    try await world.run(empty, deltaTime: 1, parallelism: 4)
    #expect(world.simulationTime == 0)
    #expect(world.lastRunStatistics.parallelTaskCount == 0)
    try await world.run(Pipeline(.none), deltaTime: 1, parallelism: 4)
    #expect(world.lastRunStatistics.systemCount == 0)
}
