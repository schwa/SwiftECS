import Foundation
import Observation
import SwiftECS

@MainActor @Observable
final class BoidsSession {
    // Views read this copy, not the world. The world is not available to them while a parallel update runs.
    private(set) var boids: [Boid] = []
    @ObservationIgnored private(set) var world = World()
    private(set) var updateMilliseconds = 0.0
    private(set) var failure: String?
    let parallelism = ProcessInfo.processInfo.activeProcessorCount
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var isUpdating = false

    init(count: Int = BoidsSettings.boidCount, seed: UInt64 = 1) {
        do {
            _ = try BoidsSystems.install(in: world)
        } catch {
            failure = String(describing: error)
        }
        var generator = SeededGenerator(seed: seed)
        for _ in 0..<count {
            let position = SIMD2(
                Double.random(in: 0..<BoidsSettings.bounds.x, using: &generator),
                Double.random(in: 0..<BoidsSettings.bounds.y, using: &generator))
            let angle = Double.random(in: 0..<(2 * .pi), using: &generator)
            let velocity = SIMD2(cos(angle), sin(angle)) * BoidsSettings.minimumSpeed
            world.createEntity(Boid(position: position, velocity: velocity))
        }
        publish()
    }

    func tick(at date: Date) async {
        guard !isUpdating, failure == nil else {
            return
        }
        defer { lastDate = date }
        guard let previous = lastDate else {
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        let deltaTime = min(max(date.timeIntervalSince(previous), 0), 1.0 / 30)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await world.update(deltaTime: deltaTime, parallelism: parallelism)
        } catch {
            failure = String(describing: error)
        }
        let elapsed = (clock.now - start).components
        updateMilliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        publish()
    }

    private func publish() {
        var boids: [Boid] = []
        boids.reserveCapacity(world.entityCount)
        for row in world.query(Boid.self) {
            boids.append(row.values)
        }
        self.boids = boids
    }
}

// SplitMix64, so every launch starts from the same flock.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
