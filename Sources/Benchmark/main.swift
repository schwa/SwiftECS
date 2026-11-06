import Foundation
import SwiftECS

struct Transform: ConcurrentComponent {
    var x: Double
    var y: Double
    var z: Double
}

struct Physics: ConcurrentComponent {
    var velocityX: Double
    var velocityY: Double
    var velocityZ: Double
}

// Stands in for per-entity logic such as steering or collision. Only x changes, so verification still holds.
@inline(never)
func simulatedWork(_ seed: Double, iterations: Int) -> Double {
    var accumulator = seed
    for _ in 0..<iterations {
        accumulator = sin(accumulator) * 0.5 + cos(accumulator) * 0.5
    }
    return accumulator * 1e-12
}

func movementSystem(matching query: Query, work: Int) -> System {
    System("MovementSystem").query(Write<Transform>(), Read<Physics>(), matching: query).each { context, transform, physics in
        var value = transform.value
        value.x += simulatedWork(value.x, iterations: work)
        value.x += physics.velocityX * context.deltaTime
        value.y += physics.velocityY * context.deltaTime
        value.z += physics.velocityZ * context.deltaTime
        transform.value = value
    }
}

func parallelMovementSystem(matching query: Query, work: Int) -> System {
    System("MovementSystem").query(Write<Transform>(), Read<Physics>(), matching: query).eachParallel(minimumRowsPerTask: 4_096) { context, row in
        let (transform, physics) = row.fields
        var value = transform.value
        value.x += simulatedWork(value.x, iterations: work)
        value.x += physics.velocityX * context.deltaTime
        value.y += physics.velocityY * context.deltaTime
        value.z += physics.velocityZ * context.deltaTime
        transform.value = value
    }
}

@MainActor func run() async throws {
    let entityCount = Int(ProcessInfo.processInfo.environment["ECS_ENTITIES"] ?? "1000000") ?? 1_000_000
    let warmupFrames = 3
    let measuredFrames = Int(ProcessInfo.processInfo.environment["ECS_FRAMES"] ?? "20") ?? 20
    let rounds = Int(ProcessInfo.processInfo.environment["ECS_ROUNDS"] ?? "5") ?? 5
    let parallelism = Int(ProcessInfo.processInfo.environment["ECS_PARALLELISM"] ?? "0") ?? 0
    let work = Int(ProcessInfo.processInfo.environment["ECS_WORK"] ?? "0") ?? 0
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
    try world.addSystem(parallelism > 0 ? parallelMovementSystem(matching: query, work: work) : movementSystem(matching: query, work: work))
    func step() async throws {
        if parallelism > 0 {
            try await world.update(deltaTime: deltaTime, parallelism: parallelism)
        } else {
            try world.update(deltaTime: deltaTime)
        }
    }
    for _ in 0..<warmupFrames {
        try await step()
    }

    let clock = ContinuousClock()
    var samples: [Double] = []
    for _ in 0..<rounds {
        let start = clock.now
        for _ in 0..<measuredFrames {
            try await step()
        }
        let duration = clock.now - start
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

try await run()
