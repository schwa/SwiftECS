import Foundation
@testable import SwiftECS
import Testing

private struct SmallValue: ConcurrentComponent { var value: Int }
private struct WideValue: ConcurrentComponent {
    var a = 0.0, b = 0.0, c = 0.0, d = 0.0, e = 0.0, f = 0.0, g = 0.0, h = 0.0
}
private struct SpreadTag: ConcurrentComponent { var bucket: Int }

private struct WriteScenario {
    let density: Int
    let wide: Bool
    let label: String
}

// Accumulates one contribution per job (no per-row contention).
private final class Sink: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var total: UInt64 = 0
    func add(_ value: UInt64) {
        lock.lock()
        total &+= value
        lock.unlock()
    }
}

// Opt-in isolation of snapshot copy, dirty-mask, and writeback costs for issue
// #40. It varies component size, write density, archetype count, and job count,
// including read-only and overlapping queries. Effects verified outside timing.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_BUFFER_BENCHMARKS"] == "1"), .serialized)
struct ParallelBufferBenchmarkTests {
    @MainActor @Test func measureBufferCosts() async throws {
        let environment = ProcessInfo.processInfo.environment
        let count = environment["ECS_BUF_ENTITIES"].flatMap(Int.init) ?? 200_000
        let rounds = environment["ECS_BUF_ROUNDS"].flatMap(Int.init) ?? 3
        let frames = environment["ECS_BUF_FRAMES"].flatMap(Int.init) ?? 10
        let limit = environment["ECS_BUF_LIMIT"].flatMap(Int.init) ?? 8
        precondition(count > 0 && rounds > 0 && frames > 0 && limit > 0)

        output("buffer OS=\(ProcessInfo.processInfo.operatingSystemVersionString) processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        #if DEBUG
        output("buffer configuration=debug (measure in Release)")
        #else
        output("buffer configuration=release")
        #endif
        output("buffer entities=\(count) rounds=\(rounds) frames=\(frames) limit=\(limit)")

        // Read-only: snapshot + slice copy + reads, no dirty mask or writeback.
        try await readOnly(count: count, rounds: rounds, frames: frames, limit: limit, wide: false)
        try await readOnly(count: count, rounds: rounds, frames: frames, limit: limit, wide: true)

        // Full write: dense dirty mask and full writeback.
        try await write(WriteScenario(density: 1, wide: false, label: "write-full-small"), count: count, rounds: rounds, frames: frames, limit: limit)
        try await write(WriteScenario(density: 1, wide: true, label: "write-full-wide"), count: count, rounds: rounds, frames: frames, limit: limit)

        // Sparse write: few dirty entries, most of the buffer/mask unused.
        try await write(WriteScenario(density: 100, wide: false, label: "write-sparse-small"), count: count, rounds: rounds, frames: frames, limit: limit)

        // Job-count sweep on the full-write small case.
        for jobs in [1, 4, 8] {
            try await write(WriteScenario(density: 1, wide: false, label: "write-jobs-\(jobs)"), count: count, rounds: rounds, frames: frames, limit: jobs)
        }

        // Archetype spread: many small batches vs one big batch.
        try await spread(count: count, buckets: 64, rounds: rounds, frames: frames, limit: limit)

        // Overlapping queries within one task share the column buffer.
        try await overlapping(count: count, rounds: rounds, frames: frames, limit: limit)
    }

    @MainActor private func readOnly(count: Int, rounds: Int, frames: Int, limit: Int, wide: Bool) async throws {
        var samples: [Double] = []
        for _ in 0..<rounds {
            let world = World()
            if wide {
                for _ in 0..<count { world.createEntity(WideValue()) }
            } else {
                for index in 0..<count { world.createEntity(SmallValue(value: index)) }
            }
            let sink = Sink()
            let system: System = wide
                ? System("read").runParallel(SystemQuery(Read<WideValue>())) { _, rows in
                    var local: UInt64 = 0
                    for row in rows { local &+= UInt64(bitPattern: Int64(row.fields.a)) &+ 1 }
                    sink.add(local)
                }
                : System("read").runParallel(SystemQuery(Read<SmallValue>())) { _, rows in
                    var local: UInt64 = 0
                    for row in rows { local &+= UInt64(truncatingIfNeeded: row.fields.value) }
                    sink.add(local)
                }
            try world.addSystem(system)
            samples.append(try await timed(world, limit: limit, frames: frames))
            #expect(sink.total > 0 || !wide)
        }
        report("read-only wide=\(wide)", samples)
    }

    @MainActor private func write(_ scenario: WriteScenario, count: Int, rounds: Int, frames: Int, limit: Int) async throws {
        var parallel: [Double] = []
        var serial: [Double] = []
        for _ in 0..<rounds {
            parallel.append(try await runWrite(scenario, count: count, frames: frames, limit: limit))
            serial.append(try await runWrite(scenario, count: count, frames: frames, limit: 1))
        }
        report("\(scenario.label) parallel", parallel)
        report("\(scenario.label) serial", serial)
    }

    @MainActor private func runWrite(_ scenario: WriteScenario, count: Int, frames: Int, limit: Int) async throws -> Double {
        let world = World()
        if scenario.wide {
            for _ in 0..<count { world.createEntity(WideValue()) }
        } else {
            for _ in 0..<count { world.createEntity(SmallValue(value: 0)) }
        }
        let density = UInt64(scenario.density)
        let system: System = scenario.wide
            ? System("w").query(Write<WideValue>()).eachParallel(minimumRowsPerTask: 1) { _, row in
                if row.entityID.value.isMultiple(of: density) { row.fields.value.a += 1 }
            }
            : System("w").query(Write<SmallValue>()).eachParallel(minimumRowsPerTask: 1) { _, row in
                if row.entityID.value.isMultiple(of: density) { row.fields.value.value += 1 }
            }
        try world.addSystem(system)
        return try await timed(world, limit: limit, frames: frames)
    }

    @MainActor private func spread(count: Int, buckets: Int, rounds: Int, frames: Int, limit: Int) async throws {
        var many: [Double] = []
        var single: [Double] = []
        for _ in 0..<rounds {
            many.append(try await runSpread(count: count, buckets: buckets, frames: frames, limit: limit))
            single.append(try await runSpread(count: count, buckets: 1, frames: frames, limit: limit))
        }
        report("archetype-spread buckets=\(buckets)", many)
        report("archetype-spread buckets=1", single)
    }

    @MainActor private func runSpread(count: Int, buckets: Int, frames: Int, limit: Int) async throws -> Double {
        let world = World()
        for index in 0..<count {
            let entity = world.createEntity(SmallValue(value: 0))
            if buckets > 1 { entity.set(SpreadTag(bucket: index % buckets)) }
        }
        let system = System("spread").query(Write<SmallValue>()).eachParallel(minimumRowsPerTask: 1) { _, row in
            row.fields.value.value += 1
        }
        try world.addSystem(system)
        return try await timed(world, limit: limit, frames: frames)
    }

    @MainActor private func overlapping(count: Int, rounds: Int, frames: Int, limit: Int) async throws {
        var samples: [Double] = []
        for _ in 0..<rounds {
            let world = World()
            for _ in 0..<count { world.createEntity(SmallValue(value: 0)) }
            let system = System("overlap").runParallel(SystemQuery(Read<SmallValue>()), SystemQuery(Write<SmallValue>())) { _, reads, writes in
                var total = 0
                for row in reads { total &+= row.fields.value }
                for row in writes { row.fields.value.value = total & 1 }
            }
            try world.addSystem(system)
            samples.append(try await timed(world, limit: limit, frames: frames))
        }
        report("overlapping-shared-buffer", samples)
    }

    @MainActor private func timed(_ world: World, limit: Int, frames: Int) async throws -> Double {
        for _ in 0..<2 { try await step(world, limit: limit) }
        let start = ContinuousClock.now
        for _ in 0..<frames { try await step(world, limit: limit) }
        return milliseconds(start.duration(to: .now)) / Double(frames)
    }

    @MainActor private func step(_ world: World, limit: Int) async throws {
        if limit == 1 {
            try world.update(deltaTime: 0)
        } else {
            try await world.update(deltaTime: 0, parallelism: limit)
        }
    }

    private func report(_ label: String, _ samples: [Double]) {
        let sorted = samples.sorted()
        output("buffer \(label) median=\(format(sorted[sorted.count / 2])) min=\(format(sorted.first!)) max=\(format(sorted.last!)) ms/frame")
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
