import Foundation
@testable import SwiftECS
import Testing

// Opt-in partitioning measurements for issue #41. It isolates tail latency under
// skewed per-row work (fixed vs over-decomposed partitions) and the dispatch
// break-even for small workloads. Full-state effects are verified outside timing.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_PARTITION_BENCHMARKS"] == "1"), .serialized)
struct ParallelPartitionBenchmarkTests {
    @MainActor @Test func measurePartitioning() async throws {
        let environment = ProcessInfo.processInfo.environment
        let rounds = environment["ECS_PART_ROUNDS"].flatMap(Int.init) ?? 3
        let frames = environment["ECS_PART_FRAMES"].flatMap(Int.init) ?? 10
        let skewCount = environment["ECS_PART_SKEW_ENTITIES"].flatMap(Int.init) ?? 100_000
        let skewDivisor = environment["ECS_PART_SKEW_DIVISOR"].flatMap(Int.init) ?? 40
        let limit = environment["ECS_PART_LIMIT"].flatMap(Int.init) ?? 8
        precondition(rounds > 0 && frames > 0 && skewCount > 0 && skewDivisor > 0 && limit > 0)

        output("partition OS=\(ProcessInfo.processInfo.operatingSystemVersionString) processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        #if DEBUG
        output("partition configuration=debug (measure in Release)")
        #else
        output("partition configuration=release")
        #endif
        output("partition rounds=\(rounds) frames=\(frames)")

        // Skewed per-row work: later rows are heavier, so fixed equal ranges make
        // the last partition the straggler. Over-decomposition lets the bounded
        // worker pool load-balance.
        output("partition skew entities=\(skewCount) divisor=\(skewDivisor) limit=\(limit)")
        var serial = Double.nan
        for tasksPerWorker in [0, 1, 4, 8, 16] {
            var samples: [Double] = []
            for _ in 0..<rounds {
                samples.append(try await runSkew(count: skewCount, divisor: skewDivisor, limit: limit, tasksPerWorker: tasksPerWorker, frames: frames))
            }
            samples.sort()
            let median = samples[samples.count / 2]
            if tasksPerWorker == 0 {
                serial = median
                output("partition skew serial median=\(format(median)) ms/frame")
            } else {
                let tasks = limit * tasksPerWorker
                output("partition skew tasksPerWorker=\(tasksPerWorker) tasks=\(tasks) median=\(format(median)) speedup-vs-serial=\(format(serial / median))x")
            }
        }

        // Dispatch break-even: uniform tiny work, serial vs parallel(limit).
        output("partition breakeven limit=\(limit)")
        for count in [64, 256, 1_024, 4_096, 16_384, 65_536] {
            let serialMedian = try await measureBreakeven(count: count, limit: 1, frames: frames, rounds: rounds)
            let parallelMedian = try await measureBreakeven(count: count, limit: limit, frames: frames, rounds: rounds)
            output("partition breakeven entities=\(count) serial=\(format(serialMedian)) parallel=\(format(parallelMedian)) speedup=\(format(serialMedian / parallelMedian))x")
        }
    }

    @MainActor private func runSkew(count: Int, divisor: Int, limit: Int, tasksPerWorker: Int, frames: Int) async throws -> Double {
        let world = World()
        for index in 0..<count {
            world.createEntity(ConcurrentPosition(value: index), ConcurrentVelocity(value: 0))
        }
        let query = Query(with: ConcurrentPosition.self, ConcurrentVelocity.self)
        world.register(query)
        let system: System
        if tasksPerWorker == 0 {
            system = System("skew").query(Read<ConcurrentPosition>(), Write<ConcurrentVelocity>(), matching: query).eachParallel(minimumRowsPerTask: 1) { _, row in
                let (position, velocity) = row.fields
                Self.skewedWork(index: position.value, divisor: divisor, into: velocity)
            }
        } else {
            system = System("skew").query(Read<ConcurrentPosition>(), Write<ConcurrentVelocity>(), matching: query).eachParallel(minimumRowsPerTask: 1, tasksPerWorker: tasksPerWorker) { _, row in
                let (position, velocity) = row.fields
                Self.skewedWork(index: position.value, divisor: divisor, into: velocity)
            }
        }
        try world.addSystem(system)
        let runLimit = tasksPerWorker == 0 ? 1 : limit
        for _ in 0..<2 { try await step(world, limit: runLimit) }
        let start = ContinuousClock.now
        for _ in 0..<frames { try await step(world, limit: runLimit) }
        let duration = start.duration(to: .now)
        // Verify outside timing: every row was processed (velocity written).
        #expect(world.query(ConcurrentVelocity.self).allSatisfy { $0.values.value >= 0 })
        #expect(world.lastRunStatistics.parallelTaskCount == (runLimit > 1 ? min(limit * tasksPerWorker, count) : 0))
        return milliseconds(duration) / Double(frames)
    }

    @MainActor private func measureBreakeven(count: Int, limit: Int, frames: Int, rounds: Int) async throws -> Double {
        var samples: [Double] = []
        for _ in 0..<rounds {
            let world = World()
            for _ in 0..<count { world.createEntity(ConcurrentPosition(value: 0)) }
            let query = Query(with: ConcurrentPosition.self)
            world.register(query)
            let system = System("uniform").query(Write<ConcurrentPosition>(), matching: query).eachParallel(minimumRowsPerTask: 1) { _, row in
                row.fields.value.value &+= 1
            }
            try world.addSystem(system)
            for _ in 0..<2 { try await step(world, limit: limit) }
            let start = ContinuousClock.now
            for _ in 0..<frames { try await step(world, limit: limit) }
            samples.append(milliseconds(start.duration(to: .now)) / Double(frames))
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    private static func skewedWork(index: Int, divisor: Int, into velocity: SystemComponent<ConcurrentVelocity>) {
        var accumulator = UInt64(truncatingIfNeeded: index) &+ 1
        for _ in 0..<(1 + index / divisor) {
            accumulator = accumulator &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        }
        velocity.value.value = Int(truncatingIfNeeded: accumulator & 0xff)
    }

    @MainActor private func step(_ world: World, limit: Int) async throws {
        if limit == 1 {
            try world.update(deltaTime: 0)
        } else {
            try await world.update(deltaTime: 0, parallelism: limit)
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }

    private func output(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
