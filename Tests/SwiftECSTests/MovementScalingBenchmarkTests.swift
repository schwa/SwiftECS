import Foundation
import SwiftECS
import Testing

// Opt-in scaling sweep for issue #39. It measures parallel movement across job
// limits and entity counts, reporting speedup, parallel efficiency, and the
// best observed limit. Phase-level timing (dispatch/join/writeback/merge)
// requires invasive core instrumentation and is tracked in #40 and #41.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_SCALING_BENCHMARKS"] == "1"), .serialized)
struct MovementScalingBenchmarkTests {
    @MainActor @Test func scaleMovement() async throws {
        let environment = ProcessInfo.processInfo.environment
        let counts = parseList(environment["ECS_SCALING_ENTITIES"]) ?? [100_000, 1_000_000]
        var limits = parseList(environment["ECS_SCALING_LIMITS"]) ?? [1, 2, 4, 8, 12, 16, 18]
        if !limits.contains(1) {
            limits.insert(1, at: 0)
        }
        limits.sort()
        let rounds = environment["ECS_SCALING_ROUNDS"].flatMap(Int.init) ?? 2
        let frames = environment["ECS_SCALING_FRAMES"].flatMap(Int.init) ?? 20
        let iterations = environment["ECS_SCALING_ITERATIONS"].flatMap(Int.init) ?? 1
        precondition(rounds > 0 && frames > 0 && iterations > 0 && counts.allSatisfy { $0 > 0 } && limits.allSatisfy { $0 > 0 })

        output("scaling OS=\(ProcessInfo.processInfo.operatingSystemVersionString) processors=\(ProcessInfo.processInfo.processorCount) active=\(ProcessInfo.processInfo.activeProcessorCount)")
        #if DEBUG
        output("scaling configuration=debug (measure in Release)")
        #else
        output("scaling configuration=release")
        #endif
        output("scaling rounds=\(rounds) frames=\(frames) iterations=\(iterations)")

        for count in counts {
            var medians: [Int: Double] = [:]
            for limit in limits {
                var samples: [Double] = []
                for _ in 0..<rounds {
                    samples.append(try await measure(entityCount: count, limit: limit, frames: frames, iterations: iterations))
                }
                samples.sort()
                let median = samples[samples.count / 2]
                medians[limit] = median
                output("scaling entities=\(count) limit=\(limit) median=\(format(median)) min=\(format(samples.first!)) max=\(format(samples.last!)) ms/frame")
            }
            guard let serial = medians[1] else {
                continue
            }
            var best = (limit: 1, median: serial)
            for limit in limits {
                guard let median = medians[limit] else {
                    continue
                }
                let speedup = serial / median
                let efficiency = speedup / Double(limit)
                output("scaling entities=\(count) limit=\(limit) speedup=\(format(speedup))x efficiency=\(format(efficiency))")
                if median < best.median {
                    best = (limit, median)
                }
            }
            output("scaling entities=\(count) best-limit=\(best.limit) best=\(format(best.median)) ms/frame best-speedup=\(format(serial / best.median))x")
        }
    }

    @MainActor private func measure(entityCount: Int, limit: Int, frames: Int, iterations: Int) async throws -> Double {
        let world = World()
        let warmupFrames = 3
        let deltaTime = 1.0 / 60
        for index in 0..<entityCount {
            world.createEntity(Transform(x: Double(index), y: 0, z: 0), Physics(velocityX: 1, velocityY: 2, velocityZ: 0))
        }
        let query = Query(with: Transform.self, Physics.self)
        world.register(query)
        let system = System("movement").query(Write<Transform>(), Read<Physics>(), matching: query).eachParallel { context, row in
            let (transform, physics) = row.fields
            var value = transform.value
            for _ in 0..<iterations {
                value.x += physics.velocityX * context.deltaTime
                value.y += physics.velocityY * context.deltaTime
                value.z += physics.velocityZ * context.deltaTime
            }
            transform.value = value
        }
        try world.addSystem(system)
        for _ in 0..<warmupFrames { try await step(world, limit: limit, deltaTime: deltaTime) }
        let start = ContinuousClock.now
        for _ in 0..<frames { try await step(world, limit: limit, deltaTime: deltaTime) }
        let duration = start.duration(to: .now)
        verify(world, count: entityCount, elapsed: Double(warmupFrames + frames) * deltaTime * Double(iterations))
        #expect(world.lastRunStatistics.parallelTaskCount == (limit > 1 ? limit : 0))
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return seconds * 1_000 / Double(frames)
    }

    @MainActor private func step(_ world: World, limit: Int, deltaTime: Double) async throws {
        if limit == 1 {
            try world.update(deltaTime: deltaTime)
        } else {
            try await world.update(deltaTime: deltaTime, parallelism: limit)
        }
    }

    private func verify(_ world: World, count: Int, elapsed: Double) {
        var visited = 0
        var incorrect = 0
        for row in world.query(Transform.self) {
            let transform: Transform = row.values
            if abs(transform.x - Double(visited) - elapsed) > 1e-6 || abs(transform.y - 2 * elapsed) > 1e-6 || transform.z != 0 {
                incorrect += 1
            }
            visited += 1
        }
        #expect(visited == count)
        #expect(incorrect == 0)
    }

    private func parseList(_ value: String?) -> [Int]? {
        guard let value else {
            return nil
        }
        let parsed = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parsed.isEmpty ? nil : parsed
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }

    private func output(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
