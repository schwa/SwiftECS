import Observation
import SwiftECS
import Testing

private enum MutationAccess: CaseIterable {
    case entity, subscriptWrite, component, row
}

// The mutation and tracking callbacks run synchronously on the test thread.
private final class MutationLog: @unchecked Sendable {
    var entries: [String] = []
    let read: () -> Void

    init(read: @escaping () -> Void) {
        self.read = read
        observe()
    }

    private func observe() {
        withObservationTracking(read) { [weak self] in
            guard let self else {
                return
            }
            entries.append("storage")
            observe()
        }
    }
}

@Test(arguments: MutationAccess.allCases)
private func `write paths publish changed state before component events and invalidate afterward`(access: MutationAccess) throws {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
    let row = try #require(world.query(Position.self, Velocity.self).first { _ in true })
    let log = MutationLog { _ = entity[Position.self] }
    let token = world.observe(Position.self) { event in
        guard case let .changed(source, value) = event else {
            Issue.record("Expected a changed event")
            return
        }
        #expect(source.id == entity.id)
        #expect(source[Position.self]?.x == 10)
        #expect(value.x == 10)
        #expect(source[Velocity.self]?.dx == (access == .row ? 20 : 3))
        log.entries.append("component")
    }
    defer { world.removeObserver(token) }
    switch access {
    case .entity:
        entity.set(Position(x: 10, y: 2))
    case .subscriptWrite:
        entity[Position.self] = Position(x: 10, y: 2)
    case .component:
        let (position, _) = row.components
        position.value.x = 10
    case .row:
        row.set(Position(x: 10, y: 2), Velocity(dx: 20, dy: 4))
    }
    #expect(log.entries == ["component", "storage"])
}

private func mutationSystem(_ action: @escaping () -> Void) -> System {
    System("MutationSystem").run { _ in action() }
}

@Test(arguments: [false, true])
private func `reentrant component callbacks preserve synchronous ordering and update batching`(batched: Bool) throws {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0))
    let log = MutationLog { _ = world.entityCount }
    let positionToken = world.observe(Position.self) { _ in
        log.entries.append("position-start")
        entity.set(Health(current: 5))
        log.entries.append("position-end")
    }
    let healthToken = world.observe(Health.self) { event in
        guard case let .added(source, value) = event else {
            Issue.record("Expected an added event")
            return
        }
        #expect(source[Health.self]?.current == value.current)
        log.entries.append("health")
    }
    defer {
        world.removeObserver(positionToken)
        world.removeObserver(healthToken)
    }
    if batched {
        try world.addSystem(mutationSystem { entity.set(Position(x: 1, y: 2)) })
        #expect(log.entries == ["storage"])
        log.entries.removeAll()
        try world.update(deltaTime: 1)
        #expect(log.entries == ["position-start", "health", "position-end", "storage"])
    } else {
        entity.set(Position(x: 1, y: 2))
        #expect(log.entries == ["position-start", "health", "storage", "position-end", "storage"])
    }
}

@Test func `removed events see the component absent before storage invalidation`() {
    let world = World()
    let entity = world.createEntity(Health(current: 7))
    let log = MutationLog { _ = entity.contains(Health.self) }
    let token = world.observe(Health.self) { event in
        guard case let .removed(source, value) = event else {
            Issue.record("Expected a removed event")
            return
        }
        #expect(!source.contains(Health.self))
        #expect(value.current == 7)
        log.entries.append("component")
    }
    defer { world.removeObserver(token) }
    entity.remove(Health.self)
    #expect(log.entries == ["component", "storage"])
    entity.remove(Health.self)
    #expect(log.entries.count == 2)
}

@Test func `entity lifecycle changes notify storage without synthesizing component events`() throws {
    let world = World()
    let log = MutationLog { _ = world.entityCount }
    var componentEvents = 0
    let token = world.observe(Health.self) { _ in componentEvents += 1 }
    defer { world.removeObserver(token) }
    let entity = world.createEntity(Health(current: 1))
    let clone = try #require(try world.clone(entity))
    try world.destroy(entity)
    try world.destroy(clone)
    #expect(log.entries == ["storage", "storage", "storage", "storage"])
    #expect(componentEvents == 0)
}

@Test func `whole row writes finish before a callback destroys the source entity`() throws {
    let world = World()
    let first = world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
    let second = world.createEntity(Position(x: 70, y: 80), Velocity(dx: 90, dy: 100))
    let row = try #require(world.query(Position.self, Velocity.self).first { $0.entityID == first.id })
    var velocityEvents = 0
    let positionToken = world.observe(Position.self) { _ in
        #expect(first[Velocity.self]?.dx == 20)
        do {
            try world.destroy(first)
        } catch {
            Issue.record(error)
        }
    }
    let velocityToken = world.observe(Velocity.self) { event in
        guard case let .changed(source, value) = event else {
            Issue.record("Expected a changed event")
            return
        }
        #expect(source.id == first.id)
        #expect(!source.exists)
        #expect(value.dx == 20)
        velocityEvents += 1
    }
    defer {
        world.removeObserver(positionToken)
        world.removeObserver(velocityToken)
    }
    row.set(Position(x: 10, y: 2), Velocity(dx: 20, dy: 4))
    #expect(velocityEvents == 1)
    #expect(second[Position.self]?.x == 70)
    #expect(second[Velocity.self]?.dx == 90)
}
