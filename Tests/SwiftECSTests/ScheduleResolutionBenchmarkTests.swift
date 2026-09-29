import Foundation
@testable import SwiftECS
import Testing

private struct ScheduleTag: Component {}

// Opt-in schedule-resolution measurements for issue #42. executionOrder(for:)
// resolves a fresh schedule without running callbacks, isolating graph
// construction and ordering from dispatch. Schedule results are verified
// outside timing.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_SCHEDULE_BENCHMARKS"] == "1"), .serialized)
struct ScheduleResolutionBenchmarkTests {
    @MainActor @Test func measureScheduleResolution() throws {
        let environment = ProcessInfo.processInfo.environment
        let rounds = environment["ECS_SCHED_ROUNDS"].flatMap(Int.init) ?? 3
        let repeats = environment["ECS_SCHED_REPEATS"].flatMap(Int.init) ?? 20
        let counts = parseList(environment["ECS_SCHED_COUNTS"]) ?? [250, 500, 1_000, 2_000]
        precondition(rounds > 0 && repeats > 0 && counts.allSatisfy { $0 > 0 })

        output("schedule OS=\(ProcessInfo.processInfo.operatingSystemVersionString) processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        #if DEBUG
        output("schedule configuration=debug (measure in Release)")
        #else
        output("schedule configuration=release")
        #endif
        output("schedule rounds=\(rounds) repeats=\(repeats)")

        for count in counts {
            try flat(count: count, rounds: rounds, repeats: repeats)
        }
        try systemChain(count: 2_000, rounds: rounds, repeats: repeats)
        try phaseChain(phases: 500, perPhase: 2, rounds: rounds, repeats: repeats)
        try widePhaseDAG(phases: 500, perPhase: 2, rounds: rounds, repeats: repeats)
        try emptyIntermediaryPhases(phases: 500, rounds: rounds, repeats: repeats)
        try subsetPipeline(count: 2_000, rounds: rounds, repeats: repeats)
        try resolveVersusRun(count: 2_000, rounds: rounds, repeats: repeats)
    }

    // Flat: N systems in the default phase, sparse dependencies.
    @MainActor private func flat(count: Int, rounds: Int, repeats: Int) throws {
        try measureResolution("flat count=\(count)", expected: count, rounds: rounds, repeats: repeats) { world in
            for index in 0..<count {
                try world.addSystem(noop("s\(index)"))
            }
        }
    }

    // System-to-system dependency chain (dense linear ordering constraints).
    @MainActor private func systemChain(count: Int, rounds: Int, repeats: Int) throws {
        try measureResolution("system-chain count=\(count)", expected: count, rounds: rounds, repeats: repeats) { world in
            for index in 0..<count {
                try world.addSystem(noop("s\(index)"), after: index > 0 ? [SystemID("s\(index - 1)")] : [])
            }
        }
    }

    // Phase chain: P phases in a DependsOn chain, systems in every phase.
    @MainActor private func phaseChain(phases: Int, perPhase: Int, rounds: Int, repeats: Int) throws {
        try measureResolution("phase-chain phases=\(phases) perPhase=\(perPhase)", expected: phases * perPhase, rounds: rounds, repeats: repeats) { world in
            var previous: [Entity] = []
            for phaseIndex in 0..<phases {
                let phase = try world.createPhase("p\(phaseIndex)", after: previous)
                for systemIndex in 0..<perPhase {
                    try world.addSystem(noop("s\(phaseIndex)_\(systemIndex)"), phase: phase)
                }
                previous = [phase]
            }
        }
    }

    // Wide DAG: many phases each depending on a common root phase.
    @MainActor private func widePhaseDAG(phases: Int, perPhase: Int, rounds: Int, repeats: Int) throws {
        try measureResolution("wide-dag phases=\(phases) perPhase=\(perPhase)", expected: (phases + 1) * perPhase, rounds: rounds, repeats: repeats) { world in
            let root = try world.createPhase("root")
            for systemIndex in 0..<perPhase {
                try world.addSystem(noop("root_\(systemIndex)"), phase: root)
            }
            for phaseIndex in 0..<phases {
                let phase = try world.createPhase("p\(phaseIndex)", after: [root])
                for systemIndex in 0..<perPhase {
                    try world.addSystem(noop("s\(phaseIndex)_\(systemIndex)"), phase: phase)
                }
            }
        }
    }

    // Long phase chain where only the first and last phases hold systems, so
    // transitive phase ancestors are materialized through empty phases.
    @MainActor private func emptyIntermediaryPhases(phases: Int, rounds: Int, repeats: Int) throws {
        try measureResolution("empty-intermediary phases=\(phases)", expected: 2, rounds: rounds, repeats: repeats) { world in
            var previous: [Entity] = []
            var chain: [Entity] = []
            for phaseIndex in 0..<phases {
                let phase = try world.createPhase("p\(phaseIndex)", after: previous)
                chain.append(phase)
                previous = [phase]
            }
            try world.addSystem(noop("first"), phase: chain.first!)
            try world.addSystem(noop("last"), phase: chain.last!)
        }
    }

    // Subset pipeline: N systems, a query selects the tagged half.
    @MainActor private func subsetPipeline(count: Int, rounds: Int, repeats: Int) throws {
        var samples: [Double] = []
        let expected = count / 2
        for _ in 0..<rounds {
            let world = World()
            for index in 0..<count {
                let entity = try world.addSystem(noop("s\(index)"))
                if index.isMultiple(of: 2) {
                    entity.set(ScheduleTag())
                }
            }
            let pipeline = Pipeline(Query(with: ScheduleTag.self))
            var resolved = 0
            let start = ContinuousClock.now
            for _ in 0..<repeats {
                resolved = try world.executionOrder(for: pipeline).count
            }
            samples.append(milliseconds(start.duration(to: .now)) / Double(repeats))
            #expect(resolved == expected)
        }
        report("subset-pipeline count=\(count) selected=\(expected)", samples, unit: "ms/resolve")
    }

    // Compare fresh resolution against a full no-op run to place resolution cost.
    @MainActor private func resolveVersusRun(count: Int, rounds: Int, repeats: Int) throws {
        var resolveSamples: [Double] = []
        var runSamples: [Double] = []
        for _ in 0..<rounds {
            let world = World()
            for index in 0..<count {
                try world.addSystem(noop("s\(index)"))
            }
            let pipeline = world.defaultPipeline
            let resolveStart = ContinuousClock.now
            for _ in 0..<repeats {
                _ = try world.executionOrder(for: pipeline)
            }
            resolveSamples.append(milliseconds(resolveStart.duration(to: .now)) / Double(repeats))
            let runStart = ContinuousClock.now
            for _ in 0..<repeats {
                try world.run(pipeline, deltaTime: 0)
            }
            runSamples.append(milliseconds(runStart.duration(to: .now)) / Double(repeats))
        }
        report("resolve-only count=\(count)", resolveSamples, unit: "ms/resolve")
        report("run-noop count=\(count)", runSamples, unit: "ms/run")
    }

    @MainActor private func measureResolution(_ label: String, expected: Int, rounds: Int, repeats: Int, build: (World) throws -> Void) throws {
        var samples: [Double] = []
        for _ in 0..<rounds {
            let world = World()
            try build(world)
            let pipeline = world.defaultPipeline
            var resolved = 0
            let start = ContinuousClock.now
            for _ in 0..<repeats {
                resolved = try world.executionOrder(for: pipeline).count
            }
            samples.append(milliseconds(start.duration(to: .now)) / Double(repeats))
            #expect(resolved == expected)
        }
        report(label, samples, unit: "ms/resolve")
    }

    @MainActor private func noop(_ id: String) -> System {
        System(SystemID(id)).run { _ in }
    }

    private func report(_ label: String, _ samples: [Double], unit: String) {
        let sorted = samples.sorted()
        output("schedule \(label) median=\(format(sorted[sorted.count / 2])) min=\(format(sorted.first!)) max=\(format(sorted.last!)) \(unit)")
    }

    private func parseList(_ value: String?) -> [Int]? {
        guard let value else {
            return nil
        }
        let parsed = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parsed.isEmpty ? nil : parsed
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
