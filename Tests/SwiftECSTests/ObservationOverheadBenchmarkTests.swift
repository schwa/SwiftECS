import Foundation
import Observation
@testable import SwiftECS
import Testing

// A rearming storage observer. Each notification counts once and rearms.
private final class RearmingObserver: @unchecked Sendable {
    var notifications = 0
    let read: () -> Void

    init(_ read: @escaping () -> Void) {
        self.read = read
        arm()
    }

    private func arm() {
        withObservationTracking(read) { [weak self] in
            guard let self else {
                return
            }
            notifications += 1
            arm()
        }
    }
}

private enum AccessStyle: CaseIterable, Sendable {
    case entityHandles
    case typedQuery

    var name: String {
        switch self {
        case .entityHandles: "entityHandles"
        case .typedQuery: "typedQuery"
        }
    }
}

// Opt-in observation-overhead measurement for issue #5. It isolates storage
// observation cost and notification volume from the work itself, across access
// styles, observer counts, and substep batching. SwiftUI body/rendering cost is
// out of scope here.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_OBSERVATION_BENCHMARKS"] == "1"), .serialized)
struct ObservationOverheadBenchmarkTests {
    @MainActor @Test func measureObservationOverhead() throws {
        let environment = ProcessInfo.processInfo.environment
        let entityCount = environment["ECS_OBS_ENTITIES"].flatMap(Int.init) ?? 100_000
        let rounds = environment["ECS_OBS_ROUNDS"].flatMap(Int.init) ?? 3
        let frames = environment["ECS_OBS_FRAMES"].flatMap(Int.init) ?? 30
        let observerCounts = [0, 1, 8]
        let substeps = 4
        precondition(entityCount > 0 && rounds > 0 && frames > 0)

        output("observation OS=\(ProcessInfo.processInfo.operatingSystemVersionString) processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        #if DEBUG
        output("observation configuration=debug (measure in Release)")
        #else
        output("observation configuration=release")
        #endif
        output("observation entities=\(entityCount) rounds=\(rounds) frames=\(frames) substeps=\(substeps)")

        // Per-frame work cost against observer count, one storage publish per frame.
        for style in AccessStyle.allCases {
            for observers in observerCounts {
                measureWork(style: style, observers: observers, entityCount: entityCount, rounds: rounds, frames: frames)
            }
        }

        // Notification volume across sequential substeps, unbatched vs batched.
        for batched in [false, true] {
            let world = makeWorld(entityCount: entityCount)
            let query = Query(with: Transform.self, Physics.self)
            world.register(query)
            let tracker = RearmingObserver { [world] in _ = world.entityCount }
            tracker.notifications = 0
            if batched {
                world.batchingObservation {
                    for _ in 0..<substeps { frame(world, style: .typedQuery, query: query) }
                }
            } else {
                for _ in 0..<substeps { frame(world, style: .typedQuery, query: query) }
            }
            output("observation substeps=\(substeps) batched=\(batched) notifications=\(tracker.notifications)")
        }
    }

    @MainActor private func measureWork(style: AccessStyle, observers: Int, entityCount: Int, rounds: Int, frames: Int) {
        var samples: [Double] = []
        var totalNotifications = 0
        for _ in 0..<rounds {
            let world = makeWorld(entityCount: entityCount)
            let query = Query(with: Transform.self, Physics.self)
            world.register(query)
            let trackers = makeObservers(world: world, count: observers, query: query)
            for _ in 0..<3 { frame(world, style: style, query: query) }
            for tracker in trackers { tracker.notifications = 0 }
            let start = ContinuousClock.now
            for _ in 0..<frames { frame(world, style: style, query: query) }
            samples.append(milliseconds(start.duration(to: .now)) / Double(frames))
            totalNotifications += trackers.reduce(0) { $0 + $1.notifications }
        }
        samples.sort()
        let notificationsPerFrame = Double(totalNotifications) / Double(rounds * frames)
        output("observation style=\(style.name) observers=\(observers) median=\(format(samples[samples.count / 2])) min=\(format(samples.first!)) max=\(format(samples.last!)) ms/frame notifications/frame=\(format(notificationsPerFrame))")
    }

    @MainActor private func makeWorld(entityCount: Int) -> World {
        let world = World()
        for index in 0..<entityCount {
            world.createEntity(Transform(x: Double(index), y: 0, z: 0), Physics(velocityX: 1, velocityY: 2, velocityZ: 0))
        }
        return world
    }

    @MainActor private func makeObservers(world: World, count: Int, query: Query) -> [RearmingObserver] {
        // Distinct reads that all depend on world-wide storage invalidation.
        (0..<count).map { index in
            switch index % 3 {
            case 0: return RearmingObserver { [world] in _ = world.entityCount }
            case 1: return RearmingObserver { [world] in _ = world.snapshot(matching: query).count }
            default: return RearmingObserver { [world] in _ = world.entities.count }
            }
        }
    }

    @MainActor private func frame(_ world: World, style: AccessStyle, query: Query) {
        let deltaTime = 1.0 / 60
        world.batchingObservation {
            switch style {
            case .entityHandles:
                for entity in world.snapshot(matching: query) {
                    guard var transform = entity[Transform.self], let physics = entity[Physics.self] else {
                        continue
                    }
                    transform.x += physics.velocityX * deltaTime
                    transform.y += physics.velocityY * deltaTime
                    transform.z += physics.velocityZ * deltaTime
                    entity.set(transform)
                }
            case .typedQuery:
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
