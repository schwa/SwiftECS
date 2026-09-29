@testable import SwiftECS
import Testing

@MainActor @Test func `default partitioning uses one partition per worker`() async throws {
    let world = World()
    for index in 0..<4_000 { world.createEntity(ConcurrentPosition(value: index)) }
    let system = System("default").query(Write<ConcurrentPosition>()).eachParallel(minimumRowsPerTask: 1) { _, row in
        row.fields.value.value += 1
    }
    try await world.run(system, deltaTime: 0, parallelism: 4)
    #expect(world.lastRunStatistics.parallelTaskCount == 4)
    #expect(world.query(ConcurrentPosition.self).allSatisfy { $0.values.value >= 1 })
}

@MainActor @Test func `over-decomposition covers every row exactly once in prepared order`() async throws {
    let world = World()
    var order: [EntityID] = []
    for index in 0..<4_000 {
        order.append(world.createEntity(ConcurrentPosition(value: index)).id)
    }
    let expectedOrder = world.snapshot(with: ConcurrentPosition.self).map(\.id)
    let system = System("split").query(Write<ConcurrentPosition>())
        .eachParallel(CreateEntities(ConcurrentMarker.self), minimumRowsPerTask: 1, tasksPerWorker: 4) { _, row, creator in
            row.fields.value.value += 1_000
            try creator.create(ConcurrentMarker(source: row.entityID))
        }
    try await world.run(system, deltaTime: 0, parallelism: 4)
    #expect(world.lastRunStatistics.parallelTaskCount == 16)
    let markers = world.snapshot(with: ConcurrentMarker.self).compactMap { $0[ConcurrentMarker.self]?.source }
    // Exact coverage: every original entity marked once, none duplicated or omitted.
    #expect(markers.count == 4_000)
    #expect(Set(markers).count == 4_000)
    // Commands merge in prepared row order regardless of task completion order.
    #expect(markers == expectedOrder)
    #expect(world.query(ConcurrentPosition.self).allSatisfy { $0.values.value >= 1_000 })
}

@MainActor @Test func `over-decomposition stays bounded by the minimum rows per task`() async throws {
    let world = World()
    for _ in 0..<10 { world.createEntity(ConcurrentPosition(value: 0)) }
    let system = System("floor").query(Write<ConcurrentPosition>()).eachParallel(minimumRowsPerTask: 8, tasksPerWorker: 8) { _, row in
        row.fields.value.value += 1
    }
    try await world.run(system, deltaTime: 0, parallelism: 4)
    // Desired 32 partitions, capped by the row floor to ceil(10/8) = 2.
    #expect(world.lastRunStatistics.parallelTaskCount == 2)
    #expect(world.query(ConcurrentPosition.self).allSatisfy { $0.values.value == 1 })
}

@Test func `non-positive tasksPerWorker is rejected at registration`() throws {
    let world = World()
    let system = System("bad").query(Read<ConcurrentPosition>()).eachParallel(tasksPerWorker: 0) { _, _ in }
    #expect(throws: SystemError.invalidPartitionSize) {
        try world.addSystem(system)
    }
    #expect(world.systemCount == 0)
}

private enum PartitionFailure: Error { case failed }

@MainActor @Test func `a failing over-decomposed partition discards only its own commands`() async throws {
    let world = World()
    for index in 0..<400 { world.createEntity(ConcurrentPosition(value: index)) }
    let system = System("partial").query(Write<ConcurrentPosition>())
        .eachParallel(CreateEntities(ConcurrentMarker.self), minimumRowsPerTask: 1, tasksPerWorker: 4) { _, row, creator in
            try creator.create(ConcurrentMarker(source: row.entityID))
            if row.fields.value.value == 250 {
                throw PartitionFailure.failed
            }
            row.fields.value.value += 1_000
        }
    await #expect(throws: PartitionFailure.self) { try await world.run(system, deltaTime: 0, parallelism: 4) }
    // The whole system's command batch is discarded on failure; immediate writes remain.
    #expect(world.snapshot(with: ConcurrentMarker.self).isEmpty)
    #expect(world.query(ConcurrentPosition.self).contains { $0.values.value >= 1_000 })
    #expect(world.reservedCommandIDs.isEmpty)
    #expect(!world.parallelRunActive)
}
