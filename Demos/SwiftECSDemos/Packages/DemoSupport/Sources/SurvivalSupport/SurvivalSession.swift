import Foundation
import Observation
import simd
import SwiftECS

@MainActor @Observable
final class SurvivalSession {
    enum Upgrade: CaseIterable {
        case magic, haste, vitality
    }

    private(set) var world = World()
    private(set) var started = false
    private(set) var paused = false
    private(set) var failure: String?
    @ObservationIgnored private var player: Entity?
    @ObservationIgnored private var system = SurvivalSystem()
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var keys: Set<String> = []

    var hero: SurvivalComponents.Hero {
        player?[SurvivalComponents.Hero.self] ?? SurvivalComponents.Hero()
    }

    var activePlayerShotCount: Int {
        guard let player else {
            return 0
        }
        let query = Query(.related(FiredBy.self, to: player.id)).with(SurvivalComponents.Shot.self)
        return world.snapshot(matching: query).count
    }

    var visibleEntityCount: Int {
        world.query(SurvivalComponents.Body.self, SurvivalComponents.Sprite.self).reduce(into: 0) { count, row in
            let body = row.values.0
            if body.position.x + body.radius >= 0, body.position.y + body.radius >= 0,
               body.position.x - body.radius <= SurvivalSystem.arena.x, body.position.y - body.radius <= SurvivalSystem.arena.y {
                count += 1
            }
        }
    }

    func start() {
        world = World()
        system = SurvivalSystem()
        do {
            try world.addSystem(system)
        } catch {
            failure = error.localizedDescription
            started = false
            paused = true
            return
        }
        player = world.createEntity(
            SurvivalComponents.Body(position: SurvivalSystem.arena / 2, radius: 18),
            SurvivalComponents.Sprite(emoji: "🧙"),
            SurvivalComponents.Hero()
        )
        started = true
        paused = false
        failure = nil
        lastDate = nil
        keys.removeAll()
    }

    func steer(to position: SIMD2<Double>) {
        guard started, !paused, !hero.finished, !hero.needsUpgrade else {
            return
        }
        system.destination = position
    }

    func releasePointer() {
        system.destination = nil
    }

    func setKey(_ key: String, pressed: Bool) {
        if pressed {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        system.destination = nil
        let horizontal = (keys.contains("d") ? 1.0 : 0) - (keys.contains("a") ? 1.0 : 0)
        let vertical = (keys.contains("s") ? 1.0 : 0) - (keys.contains("w") ? 1.0 : 0)
        system.direction = SIMD2(horizontal, vertical)
    }

    func setPaused(_ value: Bool) {
        paused = value
        clearInput()
    }

    func choose(_ upgrade: Upgrade) {
        var state = hero
        guard state.needsUpgrade else {
            return
        }
        switch upgrade {
        case .magic:
            state.damage += 1
        case .haste:
            state.fireInterval = max(0.1, state.fireInterval * 0.8)
            state.speed += 15
        case .vitality:
            state.maximumHealth += 1
            state.health = state.maximumHealth
        }
        state.needsUpgrade = false
        player?.set(state)
        clearInput()
    }

    func tick(at date: Date) {
        guard started, !paused, !hero.finished, !hero.needsUpgrade else {
            clearInput()
            return
        }
        defer { lastDate = date }
        guard let previous = lastDate else {
            return
        }
        var remaining = min(max(date.timeIntervalSince(previous), 0), 0.1)
        do {
            while remaining > 0, !hero.finished, !hero.needsUpgrade {
                let step = min(remaining, 1.0 / 120)
                try world.update(deltaTime: step)
                remaining -= step
            }
        } catch {
            failure = error.localizedDescription
            setPaused(true)
        }
    }

    private func clearInput() {
        keys.removeAll()
        system.direction = .zero
        system.destination = nil
        lastDate = nil
    }
}
