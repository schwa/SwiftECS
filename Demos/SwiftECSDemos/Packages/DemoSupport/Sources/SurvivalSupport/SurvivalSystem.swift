import Foundation
import simd
import SwiftECS

final class SurvivalSystem {
    private typealias Hero = SurvivalComponents.Hero
    private typealias Body = SurvivalComponents.Body
    private typealias Enemy = SurvivalComponents.Enemy
    private typealias Shot = SurvivalComponents.Shot

    static let arena = SIMD2<Double>(1_000, 700)
    var direction = SIMD2<Double>.zero
    var destination: SIMD2<Double>?
    private var spawnCooldown = 0.6
    private var fireCooldown = 0.0
    private var spawnCount = 0
    private var isRunningStep = false

    var systems: [System] {
        [movement, spawning, enemies, firing, shots, combat, gems, leveling]
    }

    func install(in world: World) throws {
        var predecessors: [SystemID] = []
        for system in systems {
            try world.addSystem(system, after: predecessors)
            predecessors = [system.id]
        }
    }

    private var movement: System {
        System("survival.movement").query(Write<Hero>(), Write<Body>()).run { [self] context, players in
            isRunningStep = false
            guard let player = players.first(where: { _ in true }) else {
                return
            }
            let (heroReference, bodyReference) = player.fields
            var hero = heroReference.value
            guard !hero.finished, !hero.needsUpgrade else {
                return
            }
            isRunningStep = true
            hero.elapsed = min(90, hero.elapsed + context.deltaTime)
            hero.invulnerability = max(0, hero.invulnerability - context.deltaTime)
            var body = bodyReference.value
            moveHero(body: &body, speed: hero.speed, deltaTime: context.deltaTime)
            bodyReference.value = body
            heroReference.value = hero
        }
    }

    private var spawning: System {
        System("survival.spawning").run(SystemQuery(Read<Hero>()), Commands()) { [self] context, players, commands in
            guard isRunningStep, let player = players.first(where: { _ in true }) else {
                return
            }
            spawnCooldown -= context.deltaTime
            guard spawnCooldown <= 0 else {
                return
            }
            let elapsed = player.fields.elapsed
            spawnCooldown += max(0.2, 0.85 - elapsed * 0.007)
            spawnCount += 1
            let edge = Int.random(in: 0..<4)
            let position: SIMD2<Double>
            switch edge {
            case 0: position = SIMD2(0, Double.random(in: 0...Self.arena.y))
            case 1: position = SIMD2(Self.arena.x, Double.random(in: 0...Self.arena.y))
            case 2: position = SIMD2(Double.random(in: 0...Self.arena.x), 0)
            default: position = SIMD2(Double.random(in: 0...Self.arena.x), Self.arena.y)
            }
            let shoots = spawnCount.isMultiple(of: 5)
            try commands.create(
                Body(position: position, radius: 17),
                SurvivalComponents.Sprite(emoji: shoots ? "😈" : "🧟"),
                Enemy(health: shoots ? 3 : 1 + Int(elapsed / 35), speed: shoots ? 45 : 65 + elapsed * 0.6, shoots: shoots, cooldown: 2)
            )
        }
    }

    private var enemies: System {
        let players = SystemQuery(Read<Body>(), matching: Query(with: Hero.self))
        let enemies = SystemQuery(Write<Body>(), Write<Enemy>())
        return System("survival.enemies").run(players, enemies, Commands()) { [self] context, players, enemies, commands in
            guard isRunningStep, let player = players.first(where: { _ in true }) else {
                return
            }
            for row in enemies {
                let (bodyReference, enemyReference) = row.fields
                var body = bodyReference.value
                var enemy = enemyReference.value
                let offset = player.fields.position - body.position
                let distance = simd_length(offset)
                if distance > 1, !enemy.shoots || distance > 260 {
                    body.position += offset / distance * min(enemy.speed * context.deltaTime, distance)
                }
                enemy.cooldown -= context.deltaTime
                if enemy.shoots, enemy.cooldown <= 0, distance > 1 {
                    enemy.cooldown = 2.2
                    let aim = atan2(offset.y, offset.x)
                    for spread in [-0.22, 0, 0.22] {
                        try createShot(commands: commands, origin: (row.entityID, body.position), velocity: SIMD2(cos(aim + spread), sin(aim + spread)) * 150, damage: 1, hostile: true)
                    }
                }
                bodyReference.value = body
                enemyReference.value = enemy
            }
        }
    }

    private var firing: System {
        let players = SystemQuery(Read<Hero>(), Read<Body>())
        let enemies = SystemQuery(Read<Body>(), matching: Query(with: Enemy.self))
        return System("survival.firing").run(players, enemies, Commands()) { [self] context, players, enemies, commands in
            guard isRunningStep, let player = players.first(where: { _ in true }) else {
                return
            }
            fireCooldown -= context.deltaTime
            guard fireCooldown <= 0 else {
                return
            }
            let (hero, body) = player.fields
            var nearest: SIMD2<Double>?
            var bestDistance = Double.infinity
            for row in enemies {
                let offset = row.fields.position - body.position
                let distance = simd_length_squared(offset)
                if distance < bestDistance {
                    bestDistance = distance
                    nearest = offset
                }
            }
            guard let nearest else {
                return
            }
            fireCooldown = hero.fireInterval
            let angle = atan2(nearest.y, nearest.x)
            let count = min(5, 1 + (hero.level - 1) / 2)
            for index in 0..<count {
                let spread = (Double(index) - Double(count - 1) / 2) * 0.14
                try createShot(commands: commands, origin: (player.entityID, body.position), velocity: SIMD2(cos(angle + spread), sin(angle + spread)) * 420, damage: hero.damage, hostile: false)
            }
        }
    }

    private var shots: System {
        System("survival.shots").run(SystemQuery(Write<Body>(), Write<Shot>()), Commands()) { [self] context, shots, commands in
            guard isRunningStep else {
                return
            }
            for row in shots {
                let (bodyReference, shotReference) = row.fields
                var body = bodyReference.value
                var shot = shotReference.value
                body.position += shot.velocity * context.deltaTime
                shot.lifetime -= context.deltaTime
                bodyReference.value = body
                shotReference.value = shot
                if shot.lifetime <= 0 || body.position.x < -40 || body.position.y < -40 || body.position.x > Self.arena.x + 40 || body.position.y > Self.arena.y + 40 {
                    commands.destroy(row.entityID)
                }
            }
        }
    }

    private var combat: System {
        let players = SystemQuery(Write<Hero>(), Read<Body>())
        let enemies = SystemQuery(Write<Enemy>(), Read<Body>())
        let shots = SystemQuery(Read<Shot>(), Read<Body>())
        return System("survival.combat").run(players, enemies, shots, Commands()) { [self] _, players, enemies, shots, commands in
            guard isRunningStep, let player = players.first(where: { _ in true }) else {
                return
            }
            let (heroReference, body) = player.fields
            var hero = heroReference.value
            var defeated: Set<EntityID> = []
            for projectile in shots {
                let (shot, shotBody) = projectile.fields
                if shot.hostile {
                    if overlaps(body, shotBody) {
                        hurt(&hero)
                        commands.destroy(projectile.entityID)
                    }
                } else {
                    for row in enemies where !defeated.contains(row.entityID) {
                        let (enemyReference, target) = row.fields
                        guard overlaps(shotBody, target) else {
                            continue
                        }
                        var enemy = enemyReference.value
                        enemy.health -= shot.damage
                        commands.destroy(projectile.entityID)
                        if enemy.health <= 0 {
                            defeated.insert(row.entityID)
                            commands.destroy(row.entityID)
                            hero.kills += 1
                            try commands.create(target, SurvivalComponents.Sprite(emoji: "💎"), SurvivalComponents.Gem())
                        } else {
                            enemyReference.value = enemy
                        }
                        break
                    }
                }
            }
            for row in enemies where !defeated.contains(row.entityID) {
                if overlaps(body, row.fields.1) {
                    hurt(&hero)
                }
            }
            heroReference.value = hero
        }
    }

    private var gems: System {
        let players = SystemQuery(Write<Hero>(), Read<Body>())
        let gems = SystemQuery(Write<Body>(), matching: Query(with: SurvivalComponents.Gem.self))
        return System("survival.gems").run(players, gems, Commands()) { [self] context, players, gems, commands in
            guard isRunningStep, let player = players.first(where: { _ in true }) else {
                return
            }
            let (heroReference, playerBody) = player.fields
            var hero = heroReference.value
            for row in gems {
                var body = row.fields.value
                let offset = playerBody.position - body.position
                let distance = simd_length(offset)
                if distance < 26 {
                    hero.experience += 1
                    commands.destroy(row.entityID)
                } else if distance < 130 {
                    body.position += offset / distance * min(distance, 300 * context.deltaTime)
                    row.fields.value = body
                }
            }
            heroReference.value = hero
        }
    }

    private var leveling: System {
        System("survival.leveling").query(Write<Hero>()).each { [self] _, reference in
            guard isRunningStep else {
                return
            }
            var hero = reference.value
            if hero.experience >= hero.experienceNeeded, !hero.finished {
                hero.experience -= hero.experienceNeeded
                hero.level += 1
                hero.needsUpgrade = true
            }
            reference.value = hero
        }
    }

    private func moveHero(body: inout Body, speed: Double, deltaTime: Double) {
        var movement = direction
        if simd_length_squared(movement) == 0, let destination {
            let offset = destination - body.position
            let distance = simd_length(offset)
            if distance > 3 {
                movement = offset / distance * min(1, distance / max(speed * deltaTime, 1))
            }
        }
        if simd_length_squared(movement) > 1 {
            movement = simd_normalize(movement)
        }
        body.position += movement * speed * deltaTime
        body.position = simd_clamp(body.position, SIMD2(repeating: body.radius), Self.arena - SIMD2(repeating: body.radius))
    }

    private func createShot(commands: SystemCommands, origin: (shooter: EntityID, position: SIMD2<Double>), velocity: SIMD2<Double>, damage: Int, hostile: Bool) throws {
        let projectile = try commands.create(
            Body(position: origin.position, radius: hostile ? 9 : 7),
            SurvivalComponents.Sprite(emoji: hostile ? "🔥" : "✨"),
            Shot(velocity: velocity, damage: damage, hostile: hostile, lifetime: 3)
        )
        commands.addRelationship(FiredBy.self, from: projectile, to: origin.shooter)
    }

    private func hurt(_ hero: inout Hero) {
        guard hero.invulnerability == 0, hero.health > 0 else {
            return
        }
        hero.health -= 1
        hero.invulnerability = 1
    }

    private func overlaps(_ first: Body, _ second: Body) -> Bool {
        simd_length_squared(first.position - second.position) < pow(first.radius + second.radius, 2)
    }
}
