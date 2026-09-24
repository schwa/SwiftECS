import Foundation
import Observation
import SwiftECS
import Testing

private enum QueryAccess: CaseIterable {
    case entity, typed
}

private struct QueryBenchmarkSystem: System {
    let access: QueryAccess
    let query: Query

    func update(world: World, deltaTime: Double) {
        switch access {
        case .entity:
            for entity in world.entities(matching: query) {
                guard var transform = entity[Transform.self], let physics = entity[Physics.self] else {
                    preconditionFailure("Benchmark entity is missing components")
                }
                transform.x += physics.velocityX * deltaTime
                transform.y += physics.velocityY * deltaTime
                transform.z += physics.velocityZ * deltaTime
                entity.set(transform, physics)
            }
        case .typed:
            for row in world.query(Transform.self, Physics.self, matching: query) {
                var (transform, physics) = row.values
                transform.x += physics.velocityX * deltaTime
                transform.y += physics.velocityY * deltaTime
                transform.z += physics.velocityZ * deltaTime
                row.set(transform, physics)
            }
        }
    }
}

// The benchmark and observation callbacks run synchronously on one thread.
private final class BenchmarkObservation: @unchecked Sendable {
    let world: World
    var notifications = 0

    init(world: World) {
        self.world = world
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = world.entityCount
        } onChange: { [weak self] in
            guard let self else {
                return
            }
            notifications += 1
            observe()
        }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_BENCHMARKS"] == "1"), .serialized)
struct QueryPerformanceTests {
    @Test func compareQueryAccess() throws {
        let entityCount = 100_000
        let warmupFrames = 2
        let measuredFrames = Int(ProcessInfo.processInfo.environment["ECS_BENCHMARK_FRAMES"] ?? "10") ?? 10
        precondition(measuredFrames > 0)
        let rounds = 3
        let accessFilter = ProcessInfo.processInfo.environment["ECS_BENCHMARK_ACCESS"]
        let accesses = QueryAccess.allCases.filter { accessFilter == nil || "\($0)" == accessFilter }
        precondition(!accesses.isEmpty, "Unknown ECS_BENCHMARK_ACCESS")
        let deltaTime = 1.0 / 60
        let clock = ContinuousClock()
        var samples: [String: [Double]] = [:]

        for round in 0..<rounds {
            for observed in [false, true] {
                for offset in accesses.indices {
                    let access = accesses[(round + offset) % accesses.count]
                    let world = World()
                    for index in 0..<entityCount {
                        world.createEntity(Transform(x: Double(index), y: 0, z: 0), Physics(velocityX: 1, velocityY: 2, velocityZ: 3))
                    }
                    let query = Query(with: Transform.self, Physics.self)
                    world.register(query)
                    try world.addSystem(QueryBenchmarkSystem(access: access, query: query))
                    let observation = observed ? BenchmarkObservation(world: world) : nil
                    for _ in 0..<warmupFrames {
                        try world.update(deltaTime: deltaTime)
                    }
                    let duration = try clock.measure {
                        for _ in 0..<measuredFrames {
                            try world.update(deltaTime: deltaTime)
                        }
                    }
                    let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                    let millisecondsPerFrame = seconds * 1_000 / Double(measuredFrames)
                    let key = "\(access), observed=\(observed)"
                    samples[key, default: []].append(millisecondsPerFrame)
                    if let observation {
                        #expect(observation.notifications == warmupFrames + measuredFrames)
                    }
                    let elapsed = Double(warmupFrames + measuredFrames) * deltaTime
                    verify(world: world, elapsed: elapsed, entityCount: entityCount)
                    output("round=\(round + 1), \(key), ms/frame=\(millisecondsPerFrame.formatted(.number.precision(.fractionLength(3))))")
                }
            }
        }
        summarize(samples)
    }

    private func summarize(_ samples: [String: [Double]]) {
        for key in samples.keys.sorted() {
            guard let values = samples[key]?.sorted(), let minimum = values.first, let maximum = values.last else {
                continue
            }
            let median = values[values.count / 2]
            output("SUMMARY \(key): median=\(median.formatted(.number.precision(.fractionLength(3)))) ms/frame, min=\(minimum.formatted(.number.precision(.fractionLength(3)))), max=\(maximum.formatted(.number.precision(.fractionLength(3))))")
        }
    }

    private func verify(world: World, elapsed: Double, entityCount: Int) {
        var count = 0
        for row in world.query(Transform.self) {
            #expect(abs(row.values.y - 2 * elapsed) < 0.000001)
            #expect(abs(row.values.z - 3 * elapsed) < 0.000001)
            count += 1
        }
        #expect(count == entityCount)
    }

    private func output(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
