import Foundation
import Observation
import SwiftECS

@MainActor @Observable
final class GameSession {
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var running = false
    private(set) var paused = false
    private(set) var failure: String?
    private(set) var world = World()
    @ObservationIgnored private var player: Entity?
    @ObservationIgnored private var lastDate: Date?

    func start() {
        world = World()
        player = world.createEntity(Position(x: 0.5, y: 0.9), Player())
        do {
            try world.addSystem(SpawnSystem().system)
            try world.addSystem(movementSystem(), after: ["spawn"])
            try world.addSystem(collisionSystem(), after: ["movement"])
            score = 0
            lives = 3
            failure = nil
            running = true
            paused = false
            lastDate = nil
        } catch {
            failure = error.localizedDescription
            running = false
        }
    }

    func move(to x: Double) {
        guard running, !paused else {
            return
        }
        player?.set(Position(x: min(max(x, 0.08), 0.92), y: 0.9))
    }

    func nudge(_ offset: Double) {
        move(to: (player?[Position.self]?.x ?? 0.5) + offset)
    }

    func setPaused(_ value: Bool) {
        paused = value
        lastDate = nil
    }

    func tick(at date: Date) {
        guard running, !paused else {
            lastDate = nil
            return
        }
        defer { lastDate = date }
        guard let previous = lastDate else {
            return
        }
        // Small substeps keep falling objects from tunneling through the catcher.
        var remaining = min(max(date.timeIntervalSince(previous), 0), 0.1)
        do {
            while remaining > 0, running {
                let step = min(remaining, 1.0 / 120)
                try world.update(deltaTime: step)
                remaining -= step
                if let state = player?[Player.self] {
                    score = state.score
                    lives = state.lives
                    running = lives > 0
                }
            }
        } catch {
            failure = error.localizedDescription
            running = false
        }
    }
}
