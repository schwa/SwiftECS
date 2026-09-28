@testable import StarfallSupport
import SwiftECS
import Testing

@MainActor @Test func `parallel movement and collision retain starfall behavior`() async throws {
    let world = World()
    let player = world.createEntity(Position(x: 0.5, y: 0.9), Player())
    let star = world.createEntity(Position(x: 0.5, y: 0.8), Velocity(y: 0.2), FallingObject(kind: .star))
    for index in 0..<1_000 {
        world.createEntity(Position(x: Double(index), y: 0), Velocity(y: 0.2))
    }
    try world.addSystem(movementSystem())
    try world.addSystem(collisionSystem(), after: ["movement"])
    try await world.update(deltaTime: 0.5, parallelism: 4)
    #expect(!star.exists)
    #expect(player[Player.self]?.score == 10)
    #expect(world.lastRunStatistics.parallelTaskCount > 2)
    #expect(world.snapshot(with: Velocity.self).allSatisfy { $0[Position.self]?.y == 0.1 })
}

@MainActor @Test func `stateful starfall spawning remains serial in a parallel run`() async throws {
    let world = World()
    let spawning = SpawnSystem().system
    #expect(!spawning.isParallelEligible)
    try world.addSystem(spawning)
    try world.addSystem(movementSystem(), after: [spawning.id])
    try await world.update(deltaTime: 0.4, parallelism: 2)
    #expect(world.snapshot(with: FallingObject.self).count == 1)
    #expect(world.lastRunStatistics.systemCount == 2)
}
