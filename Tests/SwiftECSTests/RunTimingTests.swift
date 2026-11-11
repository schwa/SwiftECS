@testable import SwiftECS
import Testing

@Test func `serial runs report per-system timings`() throws {
    let world = World()
    world.createEntity(Position(x: 0, y: 0))
    try world.addSystem(System("a").query(Read<Position>()).each { _, _ in })
    try world.addSystem(System("b").run { _ in })
    try world.update(deltaTime: 1)
    let statistics = world.lastRunStatistics
    #expect(statistics.systemTimings.map(\.id) == ["a", "b"])
    #expect(statistics.systemTimings.allSatisfy { !$0.ranInParallel && $0.duration >= .zero })
    #expect(statistics.totalDuration >= statistics.resolveDuration)
    #expect(statistics.totalDuration > .zero)
    #expect(statistics.parallelPhases == ParallelPhaseDurations())
}

@MainActor
@Test func `parallel runs report phase timings`() async throws {
    let world = World()
    for index in 0..<2_000 {
        world.createEntity(ConcurrentPosition(value: index))
    }
    try world.addSystem(System("move").query(Write<ConcurrentPosition>()).eachParallel(minimumRowsPerTask: 100) { _, row in
        row.fields.value.value += 1
    })
    try await world.update(deltaTime: 1, parallelism: 4)
    let statistics = world.lastRunStatistics
    #expect(statistics.systemTimings.map(\.id) == ["move"])
    #expect(statistics.systemTimings.first?.ranInParallel == true)
    #expect(statistics.parallelPhases.execute > .zero)
    #expect(statistics.parallelPhases.workerBusy > .zero)
    #expect(statistics.totalDuration >= statistics.parallelPhases.execute)
}
