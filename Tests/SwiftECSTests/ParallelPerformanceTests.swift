import Foundation
import SwiftECS
import Testing

private enum ChannelOne: Sendable {}
private enum ChannelTwo: Sendable {}
private enum ChannelThree: Sendable {}
private enum ChannelFour: Sendable {}
private struct WorkValue<Channel: Sendable>: ConcurrentComponent { var value: UInt64 }

private enum ParallelWorkload: CaseIterable, Sendable {
    case idle, compute, memory, conflicting, commands, partitioned

    var iterations: Int { self == .memory || self == .commands ? 0 : 512 }

    static func transform(_ value: UInt64, iterations: Int) -> UInt64 {
        var result = value &+ 1
        for _ in 0..<iterations {
            result = (result &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407) ^ (result >> 17)
        }
        return result
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_PARALLEL_BENCHMARKS"] == "1"), .serialized)
struct ParallelPerformanceTests {
    @MainActor @Test func compareParallelWorkloads() async throws {
        output("parallel benchmark OS=\(ProcessInfo.processInfo.operatingSystemVersionString) processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        #if DEBUG
        output("configuration=debug")
        #else
        output("configuration=release")
        #endif
        for round in 0..<2 {
            for workload in ParallelWorkload.allCases {
                for count in [64, 4_096] {
                    for offset in 0..<3 {
                        let parallelism = [1, 2, 4][(offset + round) % 3]
                        try await measure(workload, count: count, parallelism: parallelism, round: round)
                    }
                }
            }
        }
    }

    @MainActor private func measure(_ workload: ParallelWorkload, count: Int, parallelism: Int, round: Int) async throws {
        let world = World()
        let ids = (0..<count).map { index in
            let value = UInt64(index)
            return world.createEntity(WorkValue<ChannelOne>(value: value), WorkValue<ChannelTwo>(value: value), WorkValue<ChannelThree>(value: value), WorkValue<ChannelFour>(value: value)).id
        }
        try world.addSystem(makeSystem(WorkValue<ChannelOne>.self, id: "one", ids: ids, workload: workload))
        if workload == .conflicting {
            for name in ["two", "three", "four"] {
                try world.addSystem(makeSystem(WorkValue<ChannelOne>.self, id: SystemID(name), ids: ids, workload: workload))
            }
        } else if workload != .partitioned {
            try world.addSystem(makeSystem(WorkValue<ChannelTwo>.self, id: "two", ids: ids, workload: workload))
            try world.addSystem(makeSystem(WorkValue<ChannelThree>.self, id: "three", ids: ids, workload: workload))
            try world.addSystem(makeSystem(WorkValue<ChannelFour>.self, id: "four", ids: ids, workload: workload))
        }
        let frames = 5
        try await step(world, parallelism: parallelism)
        let start = ContinuousClock.now
        for _ in 0..<frames { try await step(world, parallelism: parallelism) }
        let duration = start.duration(to: .now)
        verify(world, type: WorkValue<ChannelOne>.self, count: count, steps: (frames + 1) * (workload == .conflicting ? 4 : 1), workload: workload)
        if workload != .conflicting, workload != .partitioned {
            verify(world, type: WorkValue<ChannelTwo>.self, count: count, steps: frames + 1, workload: workload)
            verify(world, type: WorkValue<ChannelThree>.self, count: count, steps: frames + 1, workload: workload)
            verify(world, type: WorkValue<ChannelFour>.self, count: count, steps: frames + 1, workload: workload)
        }
        let milliseconds = (Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15) / Double(frames)
        output("parallel round=\(round + 1) workload=\(workload) entities=\(count) limit=\(parallelism) ms/frame=\(milliseconds) tasks=\(world.lastRunStatistics.parallelTaskCount) batches=\(world.lastRunStatistics.parallelBatchCount) merges=\(world.lastRunStatistics.mergeCount)")
    }

    @MainActor private func step(_ world: World, parallelism: Int) async throws {
        if parallelism == 1 {
            try world.update(deltaTime: 1)
        } else {
            try await world.update(deltaTime: 1, parallelism: parallelism)
        }
    }

    private func makeSystem<Channel: Sendable>(_: WorkValue<Channel>.Type, id: SystemID, ids: [EntityID], workload: ParallelWorkload) -> System {
        if workload == .idle {
            return System(id).runParallel { _ in }
        }
        if workload == .commands {
            return System(id).runParallel(EditComponent<WorkValue<Channel>>()) { _, commands in
                for id in ids { try commands.set(WorkValue(value: 1), on: id) }
            }
        }
        if workload == .partitioned {
            return System(id).query(Write<WorkValue<Channel>>()).eachParallel(minimumRowsPerTask: 128) { _, row in
                let reference: SystemComponent<WorkValue<Channel>> = row.fields
                reference.value = WorkValue(value: ParallelWorkload.transform(reference.value.value, iterations: workload.iterations))
            }
        }
        return System(id).query(Write<WorkValue<Channel>>()).runParallel { _, rows in
            for row in rows {
                let reference: SystemComponent<WorkValue<Channel>> = row.fields
                reference.value = WorkValue(value: ParallelWorkload.transform(reference.value.value, iterations: workload.iterations))
            }
        }
    }

    private func verify<Channel: Sendable>(_ world: World, type: WorkValue<Channel>.Type, count: Int, steps: Int, workload: ParallelWorkload) {
        var values: [UInt64] = []
        for row in world.query(type) {
            let value: WorkValue<Channel> = row.values
            values.append(value.value)
        }
        #expect(values.count == count)
        for index in [0, count - 1] {
            var expected = UInt64(index)
            if workload != .idle {
                for _ in 0..<steps { expected = ParallelWorkload.transform(expected, iterations: workload.iterations) }
            }
            #expect(values[index] == (workload == .commands ? 1 : expected))
        }
    }

    private func output(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
