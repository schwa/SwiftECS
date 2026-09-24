import Foundation
@testable import SurvivalSupport
import SwiftECS
import Testing

@MainActor @Test func `survival steering is clamped and pause freezes the world`() throws {
    let game = SurvivalSession()
    game.start()
    let player = try #require(game.world.snapshot(with: SurvivalComponents.Hero.self).first)
    let start = try #require(player[SurvivalComponents.Body.self]).position
    let now = Date()
    game.setKey("d", pressed: true)
    game.tick(at: now)
    game.tick(at: now.addingTimeInterval(0.1))
    #expect(player[SurvivalComponents.Body.self]!.position.x > start.x)
    game.setPaused(true)
    let time = game.world.simulationTime
    game.tick(at: now.addingTimeInterval(1))
    #expect(game.world.simulationTime == time)
    game.setPaused(false)
    player.set(SurvivalComponents.Body(position: SIMD2(999, 350), radius: 18))
    game.setKey("d", pressed: true)
    game.tick(at: now.addingTimeInterval(2))
    game.tick(at: now.addingTimeInterval(2.1))
    #expect(player[SurvivalComponents.Body.self]!.position.x <= 982)
}

@Test func `survival kills drop gems and contacts respect invulnerability`() throws {
    let world = World()
    let player = world.createEntity(SurvivalComponents.Hero(), SurvivalComponents.Body(position: SIMD2(500, 350), radius: 18))
    let enemy = world.createEntity(SurvivalComponents.Body(position: SIMD2(600, 350), radius: 17), SurvivalComponents.Enemy(health: 1, speed: 0, shoots: false, cooldown: 10))
    world.createEntity(SurvivalComponents.Body(position: SIMD2(600, 350), radius: 7), SurvivalComponents.Shot(velocity: .zero, damage: 1, hostile: false, lifetime: 1))
    let system = SurvivalSystem()
    system.update(world: world, deltaTime: 0.01)
    #expect(!enemy.exists)
    #expect(player[SurvivalComponents.Hero.self]?.kills == 1)
    #expect(world.snapshot(with: SurvivalComponents.Gem.self).count == 1)
    for _ in 0..<3 {
        world.createEntity(SurvivalComponents.Body(position: SIMD2(500, 350), radius: 17), SurvivalComponents.Enemy(health: 10, speed: 0, shoots: false, cooldown: 10))
    }
    system.update(world: world, deltaTime: 0.01)
    #expect(player[SurvivalComponents.Hero.self]?.health == 4)
    system.update(world: world, deltaTime: 0.01)
    #expect(player[SurvivalComponents.Hero.self]?.health == 4)
}

@MainActor @Test func `gems offer upgrades and restart clears the run`() throws {
    let game = SurvivalSession()
    game.start()
    let player = try #require(game.world.snapshot(with: SurvivalComponents.Hero.self).first)
    for _ in 0..<5 {
        game.world.createEntity(SurvivalComponents.Body(position: SIMD2(500, 350), radius: 10), SurvivalComponents.Gem())
    }
    let now = Date()
    game.tick(at: now)
    game.tick(at: now.addingTimeInterval(0.02))
    #expect(game.hero.needsUpgrade)
    #expect(game.hero.level == 2)
    let time = game.world.simulationTime
    game.tick(at: now.addingTimeInterval(1))
    #expect(game.world.simulationTime == time)
    game.choose(.magic)
    #expect(!game.hero.needsUpgrade)
    #expect(game.hero.damage == 2)
    var hero = game.hero
    hero.health = 0
    player.set(hero)
    game.tick(at: now.addingTimeInterval(2))
    #expect(game.world.simulationTime == time)
    game.start()
    #expect(game.hero.health == 5)
    #expect(game.hero.level == 1)
    #expect(game.world.entityCount == 3)
    #expect(game.world.systemCount == 1)
}

@Test func `demons fire three hostile shots and expired shots disappear`() {
    let world = World()
    world.createEntity(SurvivalComponents.Hero(), SurvivalComponents.Body(position: SIMD2(500, 350), radius: 18))
    world.createEntity(SurvivalComponents.Body(position: SIMD2(800, 350), radius: 17), SurvivalComponents.Enemy(health: 3, speed: 0, shoots: true, cooldown: 0))
    let expired = world.createEntity(SurvivalComponents.Body(position: SIMD2(100, 100), radius: 7), SurvivalComponents.Shot(velocity: .zero, damage: 1, hostile: false, lifetime: 0.001))
    SurvivalSystem().update(world: world, deltaTime: 0.01)
    let hostile = world.snapshot(with: SurvivalComponents.Shot.self).filter { $0[SurvivalComponents.Shot.self]?.hostile == true }
    #expect(hostile.count == 3)
    #expect(!expired.exists)
}

@MainActor @Test func `haste and vitality upgrades apply only at level up`() throws {
    let game = SurvivalSession()
    game.start()
    let player = try #require(game.world.snapshot(with: SurvivalComponents.Hero.self).first)
    game.choose(.magic)
    #expect(game.hero.damage == 1)
    var hero = game.hero
    hero.needsUpgrade = true
    player.set(hero)
    game.choose(.haste)
    #expect(game.hero.fireInterval < 0.45)
    #expect(game.hero.speed > 210)
    hero = game.hero
    hero.health = 1
    hero.needsUpgrade = true
    player.set(hero)
    game.choose(.vitality)
    #expect(game.hero.health == 6)
    #expect(game.hero.maximumHealth == 6)
}

@MainActor @Test func `HUD counts visible sprites and excludes offscreen entities`() {
    let game = SurvivalSession()
    game.start()
    #expect(game.visibleEntityCount == 1)
    game.world.createEntity(SurvivalComponents.Body(position: SIMD2(-5, 100), radius: 10), SurvivalComponents.Sprite(emoji: "🔥"))
    game.world.createEntity(SurvivalComponents.Body(position: SIMD2(-50, 100), radius: 10), SurvivalComponents.Sprite(emoji: "🔥"))
    game.world.createEntity(SurvivalComponents.Body(position: SIMD2(100, 100), radius: 10))
    #expect(game.visibleEntityCount == 2)
    #expect(game.world.entityCount == 6)
}

@MainActor @Test func `projectile ownership drives the HUD and detaches when a shooter dies`() throws {
    let game = SurvivalSession()
    game.start()
    let player = try #require(game.world.snapshot(with: SurvivalComponents.Hero.self).first)
    let demon = game.world.createEntity(
        SurvivalComponents.Body(position: SIMD2(800, 350), radius: 17),
        SurvivalComponents.Enemy(health: 3, speed: 0, shoots: true, cooldown: 0)
    )
    let now = Date()
    game.tick(at: now)
    game.tick(at: now.addingTimeInterval(0.01))
    #expect(game.activePlayerShotCount == 1)
    let playerShots = game.world.snapshot(matching: Query(.related(FiredBy.self, to: player.id)))
    let demonShots = game.world.snapshot(matching: Query(.related(FiredBy.self, to: demon.id)))
    #expect(playerShots.count == 1)
    #expect(demonShots.count == 3)
    #expect(demonShots.allSatisfy { $0[SurvivalComponents.Shot.self]?.hostile == true })
    #expect(player.sources(of: FiredBy.self).count == 1)
    try game.world.destroy(demon)
    #expect(demonShots.allSatisfy { $0.exists && $0.targets(of: FiredBy.self).isEmpty })
    #expect(demonShots.allSatisfy { $0[SurvivalComponents.Shot.self]?.hostile == true })
    #expect(game.activePlayerShotCount == 1)
    for projectile in playerShots {
        var shot = try #require(projectile[SurvivalComponents.Shot.self])
        shot.lifetime = 0
        projectile.set(shot)
    }
    game.tick(at: now.addingTimeInterval(0.02))
    #expect(game.activePlayerShotCount == 0)
    #expect(player.sources(of: FiredBy.self).isEmpty)
    game.start()
    #expect(game.activePlayerShotCount == 0)
}

@Test func `surviving ninety seconds ends the run`() {
    let world = World()
    var hero = SurvivalComponents.Hero()
    hero.elapsed = 89.99
    let player = world.createEntity(hero, SurvivalComponents.Body(position: SIMD2(500, 350), radius: 18))
    SurvivalSystem().update(world: world, deltaTime: 0.02)
    #expect(player[SurvivalComponents.Hero.self]?.elapsed == 90)
    #expect(player[SurvivalComponents.Hero.self]?.finished == true)
}
