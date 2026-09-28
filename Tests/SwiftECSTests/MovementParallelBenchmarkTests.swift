import Foundation
import SwiftECS
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_MOVEMENT_BENCHMARKS"] == "1"), .serialized)
struct MovementParallelBenchmarkTests {
    @MainActor @Test func compareMovement100K() async throws {
        let environment = ProcessInfo.processInfo.environment
        let modes = environment["ECS_MOVEMENT_MODE"].flatMap(Int.init).map { [$0] } ?? [0, 1, 2, 4, 8]
        let rounds = environment["ECS_MOVEMENT_ROUNDS"].flatMap(Int.init) ?? 3
        let frames = environment["ECS_MOVEMENT_FRAMES"].flatMap(Int.init) ?? 60
        precondition(rounds > 0 && frames > 0 && modes.allSatisfy { [0, 1, 2, 4, 8].contains($0) })
        var samples: [Int: [Double]] = [:]
        output("movement100k OS=\(ProcessInfo.processInfo.operatingSystemVersionString) processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        for round in 0..<rounds {
            for offset in modes.indices {
                let mode = modes[(offset + round * 2) % modes.count]
                let elapsed = try await measure(mode: mode, measuredFrames: frames)
                samples[mode, default: []].append(elapsed)
                output("movement100k round=\(round + 1) mode=\(name(mode)) ms/frame=\(elapsed)")
            }
        }
        for mode in modes {
            let values = samples[mode, default: []].sorted()
            #expect(values.count == rounds)
            output("SUMMARY movement100k mode=\(name(mode)) median=\(values[values.count / 2]) min=\(values[0]) max=\(values[values.count - 1]) ms/frame")
        }
    }

    @MainActor private func measure(mode: Int, measuredFrames: Int) async throws -> Double {
        let world = World()
        let entityCount = 100_000
        let warmupFrames = 3
        let deltaTime = 1.0 / 60
        for index in 0..<entityCount {
            world.createEntity(Transform(x: Double(index), y: 0, z: 0), Physics(velocityX: 1, velocityY: 2, velocityZ: 0))
        }
        let query = Query(with: Transform.self, Physics.self)
        world.register(query)
        if mode != 0 {
            let system = System("movement").query(Write<Transform>(), Read<Physics>(), matching: query).eachParallel { context, row in
                let (transform, physics) = row.fields
                transform.value.x += physics.velocityX * context.deltaTime
                transform.value.y += physics.velocityY * context.deltaTime
                transform.value.z += physics.velocityZ * context.deltaTime
            }
            try world.addSystem(system)
        }
        for _ in 0..<warmupFrames { try await step(world, query: query, mode: mode, deltaTime: deltaTime) }
        if let ready = ProcessInfo.processInfo.environment["ECS_MOVEMENT_PROFILE_READY"] {
            try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: URL(fileURLWithPath: ready))
        }
        let start = ContinuousClock.now
        for _ in 0..<measuredFrames { try await step(world, query: query, mode: mode, deltaTime: deltaTime) }
        let duration = start.duration(to: .now)
        verify(world, count: entityCount, elapsed: Double(warmupFrames + measuredFrames) * deltaTime)
        #expect(world.lastRunStatistics.parallelTaskCount == (mode > 1 ? mode : 0))
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return seconds * 1_000 / Double(measuredFrames)
    }

    @MainActor private func step(_ world: World, query: Query, mode: Int, deltaTime: Double) async throws {
        if mode == 0 {
            for row in world.query(Transform.self, Physics.self, matching: query) {
                let (transform, physics) = row.components
                transform.value.x += physics.value.velocityX * deltaTime
                transform.value.y += physics.value.velocityY * deltaTime
                transform.value.z += physics.value.velocityZ * deltaTime
            }
        } else if mode == 1 {
            try world.update(deltaTime: deltaTime)
        } else {
            try await world.update(deltaTime: deltaTime, parallelism: mode)
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
        let physicsCorrect = world.query(Physics.self).allSatisfy { row in
            let physics: Physics = row.values
            return physics.velocityX == 1 && physics.velocityY == 2 && physics.velocityZ == 0
        }
        #expect(physicsCorrect)
    }

    private func name(_ mode: Int) -> String {
        mode == 0 ? "raw-loop" : mode == 1 ? "system-serial" : "system-\(mode)-jobs"
    }

    private func output(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
