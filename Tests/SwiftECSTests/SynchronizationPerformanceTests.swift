import Foundation
import SwiftECS
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_SYNC_BENCHMARKS"] == "1"), .serialized)
struct SynchronizationPerformanceTests {
    @Test func compareSynchronizationPolicies() throws {
        let policies: [PipelineSynchronization] = [.automatic, .afterEachSystem]
        for round in 0..<3 {
            for offset in policies.indices {
                try measure(policies[(round + offset) % policies.count], round: round)
            }
        }
    }

    private func measure(_ policy: PipelineSynchronization, round: Int) throws {
        let world = World()
        let producerCount = 32
        let entitiesPerProducer = 128
        let frames = 20
        for producer in 0..<producerCount {
            let ids = (0..<entitiesPerProducer).map { _ in world.createEntity(Health(current: 0)).id }
            try world.addSystem(System(SystemID("producer-\(producer)")).run(EditComponent<Health>()) { _, health in
                for id in ids {
                    try health.set(Health(current: 1), on: id)
                }
            })
        }
        var checksum = 0
        try world.addSystem(System("reader").query(Read<Health>()).run { _, rows in
            checksum = rows.reduce(0) { $0 + $1.fields.current }
        })
        let pipeline = Pipeline(synchronization: policy)
        for _ in 0..<2 {
            try world.run(pipeline, deltaTime: 0)
        }
        let duration = try ContinuousClock().measure {
            for _ in 0..<frames {
                try world.run(pipeline, deltaTime: 0)
            }
        }
        #expect(checksum == producerCount * entitiesPerProducer)
        #expect(world.lastRunStatistics.commandCount == producerCount * entitiesPerProducer)
        #expect(world.lastRunStatistics.mergeCount == (policy == .automatic ? 1 : producerCount))
        let milliseconds = (Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15) / Double(frames)
        let output = "sync round=\(round + 1) policy=\(policy) merges/frame=\(world.lastRunStatistics.mergeCount) commands/frame=\(world.lastRunStatistics.commandCount) ms/frame=\(milliseconds)\n"
        FileHandle.standardOutput.write(Data(output.utf8))
    }
}
