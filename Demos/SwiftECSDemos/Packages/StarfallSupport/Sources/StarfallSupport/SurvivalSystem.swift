import ECS
import Foundation
import simd

final class SurvivalSystem: System {
    static let arena = SIMD2<Double>(1_000, 700)
    var direction = SIMD2<Double>.zero
    var destination: SIMD2<Double>?
    private var spawnCooldown = 0.6
    private var fireCooldown = 0.0
    private var spawnCount = 0

    func update(world: World, deltaTime: Double) {
        guard let player = world.query(with: SurvivalComponents.Hero.self).first,
              var hero = player[SurvivalComponents.Hero.self], var body = player[SurvivalComponents.Body.self],
              !hero.finished, !hero.needsUpgrade else {
            return
        }
        hero.elapsed = min(90, hero.elapsed + deltaTime)
        hero.invulnerability = max(0, hero.invulnerability - deltaTime)
        moveHero(body: &body, speed: hero.speed, deltaTime: deltaTime)
        spawn(world: world, elapsed: hero.elapsed, deltaTime: deltaTime)
        moveEnemies(world: world, target: body.position, deltaTime: deltaTime)
        fire(world: world, shooter: player, body: body, hero: hero, deltaTime: deltaTime)
        moveShots(world: world, deltaTime: deltaTime)
        resolveCombat(world: world, hero: &hero, body: body)
        collectGems(world: world, hero: &hero, position: body.position, deltaTime: deltaTime)
        if hero.experience >= hero.experienceNeeded, !hero.finished {
            hero.experience -= hero.experienceNeeded
            hero.level += 1
            hero.needsUpgrade = true
        }
        player.set(body, hero)
    }

    private func moveHero(body: inout SurvivalComponents.Body, speed: Double, deltaTime: Double) {
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

    private func spawn(world: World, elapsed: Double, deltaTime: Double) {
        spawnCooldown -= deltaTime
        guard spawnCooldown <= 0 else {
            return
        }
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
        world.createEntity(
            SurvivalComponents.Body(position: position, radius: 17),
            SurvivalComponents.Sprite(emoji: shoots ? "😈" : "🧟"),
            SurvivalComponents.Enemy(health: shoots ? 3 : 1 + Int(elapsed / 35), speed: shoots ? 45 : 65 + elapsed * 0.6, shoots: shoots, cooldown: 2)
        )
    }

    private func moveEnemies(world: World, target: SIMD2<Double>, deltaTime: Double) {
        var launches: [(EntityID, SIMD2<Double>)] = []
        for row in world.typedQuery(SurvivalComponents.Body.self, SurvivalComponents.Enemy.self) {
            var (body, enemy) = row.values
            let offset = target - body.position
            let distance = simd_length(offset)
            if distance > 1, !enemy.shoots || distance > 260 {
                body.position += offset / distance * min(enemy.speed * deltaTime, distance)
            }
            enemy.cooldown -= deltaTime
            if enemy.shoots, enemy.cooldown <= 0, distance > 1 {
                enemy.cooldown = 2.2
                let aim = atan2(offset.y, offset.x)
                for spread in [-0.22, 0, 0.22] {
                    launches.append((row.entityID, SIMD2(cos(aim + spread), sin(aim + spread)) * 150))
                }
            }
            row.set(body, enemy)
        }
        for (shooterID, velocity) in launches {
            guard let shooter = world[shooterID], let body = shooter[SurvivalComponents.Body.self] else {
                continue
            }
            createShot(world: world, origin: (shooter, body.position), velocity: velocity, damage: 1, hostile: true)
        }
    }

    private func fire(world: World, shooter: Entity, body: SurvivalComponents.Body, hero: SurvivalComponents.Hero, deltaTime: Double) {
        fireCooldown -= deltaTime
        guard fireCooldown <= 0 else {
            return
        }
        var nearest: SIMD2<Double>?
        var bestDistance = Double.infinity
        for row in world.typedQuery(SurvivalComponents.Body.self, SurvivalComponents.Enemy.self) {
            let offset = row.values.0.position - body.position
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
            createShot(world: world, origin: (shooter, body.position), velocity: SIMD2(cos(angle + spread), sin(angle + spread)) * 420, damage: hero.damage, hostile: false)
        }
    }

    private func createShot(world: World, origin: (shooter: Entity, position: SIMD2<Double>), velocity: SIMD2<Double>, damage: Int, hostile: Bool) {
        let projectile = world.createEntity(
            SurvivalComponents.Body(position: origin.position, radius: hostile ? 9 : 7),
            SurvivalComponents.Sprite(emoji: hostile ? "🔥" : "✨"),
            SurvivalComponents.Shot(velocity: velocity, damage: damage, hostile: hostile, lifetime: 3)
        )
        do {
            try projectile.addRelationship(FiredBy.self, to: origin.shooter)
        } catch {
            preconditionFailure("A new projectile must have a live shooter in the same world: \(error)")
        }
    }

    private func moveShots(world: World, deltaTime: Double) {
        var expired: [EntityID] = []
        for row in world.typedQuery(SurvivalComponents.Body.self, SurvivalComponents.Shot.self) {
            var (body, shot) = row.values
            body.position += shot.velocity * deltaTime
            shot.lifetime -= deltaTime
            row.set(body, shot)
            if shot.lifetime <= 0 || body.position.x < -40 || body.position.y < -40 || body.position.x > Self.arena.x + 40 || body.position.y > Self.arena.y + 40 {
                expired.append(row.entityID)
            }
        }
        for id in expired {
            if let entity = world[id] {
                world.destroy(entity)
            }
        }
    }

    private func resolveCombat(world: World, hero: inout SurvivalComponents.Hero, body: SurvivalComponents.Body) {
        let enemies = world.query(with: SurvivalComponents.Enemy.self)
        for shotEntity in world.query(with: SurvivalComponents.Shot.self) {
            guard let shot = shotEntity[SurvivalComponents.Shot.self], let shotBody = shotEntity[SurvivalComponents.Body.self] else {
                continue
            }
            if shot.hostile {
                if overlaps(body, shotBody) {
                    hurt(&hero)
                    world.destroy(shotEntity)
                }
            } else {
                hitEnemy(world: world, enemies: enemies, projectile: shotEntity, hero: &hero)
            }
        }
        for enemy in enemies {
            if let enemyBody = enemy[SurvivalComponents.Body.self], overlaps(body, enemyBody) {
                hurt(&hero)
            }
        }
    }

    private func hitEnemy(world: World, enemies: [Entity], projectile: Entity, hero: inout SurvivalComponents.Hero) {
        guard let shot = projectile[SurvivalComponents.Shot.self], let body = projectile[SurvivalComponents.Body.self] else {
            return
        }
        for entity in enemies {
            guard var enemy = entity[SurvivalComponents.Enemy.self], let target = entity[SurvivalComponents.Body.self], overlaps(body, target) else {
                continue
            }
            enemy.health -= shot.damage
            world.destroy(projectile)
            if enemy.health <= 0 {
                world.destroy(entity)
                hero.kills += 1
                world.createEntity(target, SurvivalComponents.Sprite(emoji: "💎"), SurvivalComponents.Gem())
            } else {
                entity.set(enemy)
            }
            break
        }
    }

    private func collectGems(world: World, hero: inout SurvivalComponents.Hero, position: SIMD2<Double>, deltaTime: Double) {
        for entity in world.query(with: SurvivalComponents.Gem.self) {
            guard var body = entity[SurvivalComponents.Body.self] else {
                continue
            }
            let offset = position - body.position
            let distance = simd_length(offset)
            if distance < 26 {
                hero.experience += 1
                world.destroy(entity)
            } else if distance < 130 {
                body.position += offset / distance * min(distance, 300 * deltaTime)
                entity.set(body)
            }
        }
    }

    private func hurt(_ hero: inout SurvivalComponents.Hero) {
        guard hero.invulnerability == 0, hero.health > 0 else {
            return
        }
        hero.health -= 1
        hero.invulnerability = 1
    }

    private func overlaps(_ first: SurvivalComponents.Body, _ second: SurvivalComponents.Body) -> Bool {
        simd_length_squared(first.position - second.position) < pow(first.radius + second.radius, 2)
    }
}
