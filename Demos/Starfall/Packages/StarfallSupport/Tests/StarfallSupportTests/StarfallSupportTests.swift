import ECS
import Foundation
import Testing
@testable import StarfallSupport

@Test func `movement uses delta time`() throws {
    let world = World()
    let entity = world.createEntity(Position(x: 0.5, y: 0.1), Velocity(y: 0.2))
    MovementSystem().update(world: world, deltaTime: 0.5)
    let position = try #require(entity[Position.self])
    #expect(abs(position.y - 0.2) < 0.00001)
}

@Test func `catching stars scores and removes them`() throws {
    let world = World()
    let player = world.createEntity(Position(x: 0.5, y: 0.9), Player())
    let star = world.createEntity(Position(x: 0.5, y: 0.9), FallingObject(kind: .star))
    CollisionSystem().update(world: world, deltaTime: 0)
    #expect(player[Player.self]?.score == 10)
    #expect(player[Player.self]?.lives == 3)
    #expect(!star.exists)
}

@Test func `meteors and missed stars cost lives but missed meteors do not`() {
    let world = World()
    let player = world.createEntity(Position(x: 0.5, y: 0.9), Player())
    world.createEntity(Position(x: 0.5, y: 0.9), FallingObject(kind: .meteor))
    world.createEntity(Position(x: 0.2, y: 1.1), FallingObject(kind: .star))
    world.createEntity(Position(x: 0.8, y: 1.1), FallingObject(kind: .meteor))
    CollisionSystem().update(world: world, deltaTime: 0)
    #expect(player[Player.self]?.lives == 1)
    #expect(world.entityCount == 1)
}

@MainActor @Test func `session pauses clamps steering and resets`() throws {
    let game = GameSession()
    game.start()
    game.move(to: -10)
    let player = try #require(game.world.query(with: Player.self).first)
    #expect(player[Position.self]?.x == 0.08)
    let now = Date()
    game.tick(at: now)
    game.tick(at: now.addingTimeInterval(0.05))
    #expect(game.world.simulationTime > 0)
    game.setPaused(true)
    let time = game.world.simulationTime
    game.tick(at: now.addingTimeInterval(5))
    #expect(game.world.simulationTime == time)
    game.start()
    #expect(game.world.entityCount == 1)
    #expect(game.world.simulationTime == 0)
    #expect(game.score == 0)
    #expect(game.lives == 3)
    #expect(!game.paused)
    #expect(game.failure == nil)
}

@MainActor @Test func `last heart ends the game and freezes simulation`() throws {
    let game = GameSession()
    game.start()
    let player = try #require(game.world.query(with: Player.self).first)
    player.set(Player(score: 20, lives: 1))
    game.world.createEntity(Position(x: 0.5, y: 0.9), FallingObject(kind: .meteor))
    let now = Date()
    game.tick(at: now)
    game.tick(at: now.addingTimeInterval(0.05))
    #expect(!game.running)
    #expect(game.lives == 0)
    #expect(game.score == 20)
    let time = game.world.simulationTime
    game.tick(at: now.addingTimeInterval(1))
    #expect(game.world.simulationTime == time)
}
