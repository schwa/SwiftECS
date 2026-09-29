import Observation
@testable import SwiftECS
import Testing

// Observation callbacks run synchronously on the test thread.
private final class BatchTracker: @unchecked Sendable {
    var count = 0
    let read: () -> Void

    init(_ read: @escaping () -> Void) {
        self.read = read
        arm()
    }

    func arm() {
        withObservationTracking(read) { [weak self] in
            guard let self else {
                return
            }
            count += 1
            arm()
        }
    }
}

private enum BatchFailure: Error { case midFrame }

private func tickSystem() -> System {
    System("tick").query(Write<Health>()).each { _, health in
        health.value.current += 1
    }
}

@Test func `sequential update substeps notify once per update without batching`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    try world.addSystem(tickSystem())
    let tracker = BatchTracker { _ = world.entityCount }
    for _ in 0..<4 {
        try world.update(deltaTime: 1)
    }
    #expect(tracker.count == 4)
    #expect(entity[Health.self]?.current == 4)
}

@Test func `batchingObservation coalesces substep storage invalidation into one notification`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    try world.addSystem(tickSystem())
    let tracker = BatchTracker { _ = world.entityCount }
    try world.batchingObservation {
        for _ in 0..<4 {
            try world.update(deltaTime: 1)
        }
    }
    #expect(tracker.count == 1)
    #expect(entity[Health.self]?.current == 4)
    // A later unbatched update still notifies normally.
    try world.update(deltaTime: 1)
    #expect(tracker.count == 2)
    #expect(entity[Health.self]?.current == 5)
}

@Test func `batchingObservation flushes the pending invalidation when a substep throws`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    try world.addSystem(tickSystem())
    let tracker = BatchTracker { _ = world.entityCount }
    #expect(throws: BatchFailure.self) {
        try world.batchingObservation {
            try world.update(deltaTime: 1)
            try world.update(deltaTime: 1)
            throw BatchFailure.midFrame
        }
    }
    // Two substeps completed before the throw; the scope still publishes once.
    #expect(tracker.count == 1)
    #expect(entity[Health.self]?.current == 2)
}

@Test func `batchingObservation returns its body result and nests`() throws {
    let world = World()
    world.createEntity(Health(current: 0))
    try world.addSystem(tickSystem())
    let tracker = BatchTracker { _ = world.entityCount }
    let total = try world.batchingObservation {
        try world.batchingObservation {
            try world.update(deltaTime: 1)
        }
        try world.update(deltaTime: 1)
        return 7
    }
    #expect(total == 7)
    #expect(tracker.count == 1)
}
