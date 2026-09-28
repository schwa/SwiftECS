@testable import SwiftECS
import Testing

@MainActor @Test(arguments: [1, 2, 4])
func `repeated partitioned updates agree with the serial reference`(parallelism: Int) async throws {
    let world = World()
    for index in 0..<513 {
        world.createEntity(ConcurrentPosition(value: index), ConcurrentVelocity(value: 1), ConcurrentHealth(value: 0))
    }
    try world.addSystem(System("move").query(Write<ConcurrentPosition>(), Read<ConcurrentVelocity>()).eachParallel(minimumRowsPerTask: 17) { _, row in
        row.fields.0.value.value += row.fields.1.value
    })
    try world.addSystem(System("health").query(Write<ConcurrentHealth>()).eachParallel(minimumRowsPerTask: 19) { _, row in
        row.fields.value.value += 2
    })
    for _ in 0..<20 { try await world.update(deltaTime: 1, parallelism: parallelism) }
    var positions: [Int] = []
    for row in world.query(ConcurrentPosition.self) {
        let value: ConcurrentPosition = row.values
        positions.append(value.value)
    }
    #expect(positions == (0..<513).map { $0 + 20 })
    #expect(world.query(ConcurrentHealth.self).allSatisfy { $0.values.value == 40 })
    #expect(world.simulationTime == 20)
    #expect(world.reservedCommandIDs.isEmpty)
}

@MainActor @Test func `parallel component and relationship removal apply only after the callback`() async throws {
    let world = World()
    let parent = world.createEntity()
    let child = world.createEntity(ConcurrentHealth(value: 1))
    try child.setParent(parent)
    let childID = child.id
    let parentID = parent.id
    let system = System("remove").runParallel(SystemQuery(Read<ConcurrentHealth>()), EditComponent<ConcurrentHealth>(), EditRelationship<ChildOf>()) { _, rows, health, parents in
        health.remove(from: childID)
        parents.remove(from: childID, to: parentID)
        #expect(rows.count { _ in true } == 1)
    }
    try await world.run(system, deltaTime: 0, parallelism: 2)
    #expect(!child.contains(ConcurrentHealth.self))
    #expect(child.parent == nil)
    #expect(world.lastRunStatistics.commandCount == 2)
}

private enum PrefixFailure: Error { case failed }

@MainActor @Test func `a failed parallel wave commits only its successful logical prefix`() async throws {
    let world = World()
    try world.addSystem(System("first").runParallel(CreateEntities(ConcurrentHealth.self)) { _, creator in
        try creator.create(ConcurrentHealth(value: 1))
    })
    try world.addSystem(System("second").runParallel(CreateEntities(ConcurrentPosition.self)) { _, creator in
        try creator.create(ConcurrentPosition(value: 2))
        throw PrefixFailure.failed
    })
    try world.addSystem(System("third").runParallel(CreateEntities(ConcurrentVelocity.self)) { _, creator in
        try creator.create(ConcurrentVelocity(value: 3))
    })
    await #expect(throws: PrefixFailure.self) { try await world.update(deltaTime: 0, parallelism: 3) }
    #expect(world.snapshot(with: ConcurrentHealth.self).count == 1)
    #expect(world.snapshot(with: ConcurrentPosition.self).isEmpty)
    #expect(world.snapshot(with: ConcurrentVelocity.self).isEmpty)
    #expect(world.lastRunStatistics.parallelTaskCount == 3)
    #expect(world.reservedCommandIDs.isEmpty)
}

@MainActor @Test func `parallel run cleanup happens after jobs join on the owning actor`() async throws {
    let world = World()
    var cleanup = false
    var victimRan = false
    let victim = try world.addSystem(System("victim").run { _ in victimRan = true }.onCleanup {
        MainActor.assertIsolated()
        #expect(world.parallelRunActive)
        #expect(!world.mutations.isParallelSuspended)
        #expect(throws: SystemError.parallelRunInProgress) { try world.update(deltaTime: 0) }
        cleanup = true
    })
    let id = victim.id
    try world.addSystem(System("destroy").runParallel(DestroyEntities()) { _, destroyer in destroyer.destroy(id) }, before: ["victim"])
    try await world.update(deltaTime: 0, parallelism: 2)
    #expect(cleanup)
    #expect(victimRan)
    #expect(!victim.exists)
}
