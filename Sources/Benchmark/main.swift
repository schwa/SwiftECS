import Foundation
import SwiftECS

struct Transform: Component {
    var x: Double
    var y: Double
    var z: Double
}

struct Physics: Component {
    var velocityX: Double
    var velocityY: Double
    var velocityZ: Double
}

struct MovementSystem: System {
    let query: Query

    func update(world: World, deltaTime: Double) {
        for row in world.query(Transform.self, Physics.self, matching: query) {
            var (transform, physics) = row.values
            transform.x += physics.velocityX * deltaTime
            transform.y += physics.velocityY * deltaTime
            transform.z += physics.velocityZ * deltaTime
            row.set(transform, physics)
        }
    }
}

@MainActor func run() throws {
    let entityCount = Int(ProcessInfo.processInfo.environment["ECS_ENTITIES"] ?? "1000000") ?? 1_000_000
    let warmupFrames = 3
    let measuredFrames = Int(ProcessInfo.processInfo.environment["ECS_FRAMES"] ?? "20") ?? 20
    let rounds = Int(ProcessInfo.processInfo.environment["ECS_ROUNDS"] ?? "5") ?? 5
    let deltaTime = 1.0 / 60
    precondition(entityCount > 0 && measuredFrames > 0 && rounds > 0)

    let world = World()
    for index in 0..<entityCount {
        world.createEntity(
            Transform(x: Double(index), y: 0, z: 0),
            Physics(velocityX: 1, velocityY: 2, velocityZ: 3))
    }
    let query = Query(with: Transform.self, Physics.self)
    world.register(query)
    try world.addSystem(MovementSystem(query: query))
    for _ in 0..<warmupFrames {
        try world.update(deltaTime: deltaTime)
    }

    let clock = ContinuousClock()
    var samples: [Double] = []
    for _ in 0..<rounds {
        let duration = try clock.measure {
            for _ in 0..<measuredFrames {
                try world.update(deltaTime: deltaTime)
            }
        }
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        samples.append(seconds * 1_000 / Double(measuredFrames))
    }
    samples.sort()
    let median = samples[samples.count / 2]
    let minimum = samples[0]
    let maximum = samples[samples.count - 1]

    // Verify correctness (not part of timing).
    let elapsed = Double(warmupFrames + measuredFrames * rounds) * deltaTime
    verify(world: world, elapsed: elapsed, entityCount: entityCount)

    FileHandle.standardError.write(Data("ms/frame median=\(median) min=\(minimum) max=\(maximum)\n".utf8))
    print("METRIC ms_per_frame=\(median)")
    print("METRIC min_ms=\(minimum)")
    print("METRIC entities_per_ms=\(Double(entityCount) / median)")
}

func verify(world: World, elapsed: Double, entityCount: Int) {
    var count = 0
    var correct = true
    for row in world.query(Transform.self, Physics.self) {
        let (transform, _) = row.values
        if abs(transform.y - 2 * elapsed) > 1e-6 || abs(transform.z - 3 * elapsed) > 1e-6 {
            correct = false
        }
        count += 1
    }
    precondition(count == entityCount, "entity count mismatch")
    precondition(correct, "verification failed")
}

try run()
