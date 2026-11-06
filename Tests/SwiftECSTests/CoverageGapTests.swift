import Foundation
import SwiftECS
import Testing

@Test func `composite compares hashes and orders element-wise`() {
    let first = Composite(1, "a")
    #expect(first == Composite(1, "a"))
    #expect(first != Composite(1, "b"))
    #expect(first != Composite(2, "a"))
    #expect(Set([first, Composite(1, "a"), Composite(2, "b")]).count == 2)
    #expect(Composite(1, 2) < Composite(2, 3))
    #expect(!(Composite(2, 3) < Composite(1, 2)))
    let same = Composite(1, 2)
    #expect(!(same < Composite(1, 2)))
    #expect(Composite(1, 5) < Composite(2, 0))
    #expect(!(Composite(2, 0) < Composite(1, 5)))
    #expect(Composite(1, 2) < Composite(1, 3))
    #expect([Composite(2, 0), Composite(1, 5), Composite(1, 2)].sorted() == [Composite(1, 2), Composite(1, 5), Composite(2, 0)])
    #expect(first.values.0 == 1)
    #expect(first.values.1 == "a")
}

@Test func `component observers receive added and removed events`() {
    let world = World()
    var events: [String] = []
    let token = world.observe(Health.self) { event in
        switch event {
        case let .added(_, value): events.append("added \(value.current)")
        case let .removed(_, value): events.append("removed \(value.current)")
        case let .changed(_, value): events.append("changed \(value.current)")
        }
    }
    defer { world.removeObserver(token) }
    let entity = world.createEntity(Position(x: 0, y: 0))
    entity.set(Health(current: 1))
    entity.set(Health(current: 2))
    _ = entity.remove(Health.self)
    #expect(events == ["added 1", "changed 2", "removed 2"])
}

@Test func `entity IDs are comparable and round-trip through Codable`() throws {
    let ids = [EntityID(), EntityID(), EntityID()]
    let sorted = ids.sorted()
    #expect(zip(sorted, sorted.dropFirst()).allSatisfy { $0.value <= $1.value })
    let data = try JSONEncoder().encode(ids)
    #expect(try JSONDecoder().decode([EntityID].self, from: data) == ids)
    #expect(try JSONDecoder().decode(EntityID.self, from: Data("42".utf8)).value == 42)
}

@Test func `component type convenience constructor matches the initializer`() {
    #expect(ComponentType.of(Position.self) == ComponentType(Position.self))
    #expect(ComponentType.of(Position.self) != ComponentType.of(Velocity.self))
}

@Test func `relationship reader reports whether an edge exists`() throws {
    let world = World()
    let parent = world.createEntity()
    let child = world.createEntity()
    let stranger = world.createEntity()
    try child.setParent(parent)
    var results: [Bool] = []
    try world.run(System("read").run(ReadRelationship<ChildOf>()) { _, links in
        results = [
            links.contains(from: child.id, to: parent.id),
            links.contains(from: stranger.id, to: parent.id),
            links.contains(from: parent.id, to: child.id)
        ]
    }, deltaTime: 0)
    #expect(results == [true, false, false])
}

@Test func `parallel run accepts a pipeline entity`() async throws {
    let world = World()
    let entity = world.createEntity(ConcurrentHealth(value: 0))
    try world.addSystem(System("bump").query(Write<ConcurrentHealth>()).runParallel { _, rows in
        for row in rows {
            row.fields.value.value += 1
        }
    })
    let pipeline = world.createEntity(Pipeline())
    try await world.run(pipeline, deltaTime: 1, parallelism: 2)
    #expect(entity[ConcurrentHealth.self]?.value == 1)
}

@Test func `parallel run rejects entities without a pipeline`() async throws {
    let world = World()
    let notPipeline = world.createEntity()
    await #expect(throws: SystemError.invalidPipeline(notPipeline.id)) {
        try await world.run(notPipeline, deltaTime: 1, parallelism: 2)
    }
}

@Test func `parallel each applies component and destroy commands`() async throws {
    let world = World()
    let keep = world.createEntity(ConcurrentHealth(value: 1))
    let doomed = world.createEntity(ConcurrentHealth(value: -1))
    let system = System("commands").query(Read<ConcurrentHealth>()).eachParallel(EditComponent<ConcurrentHealth>(), DestroyEntities()) { _, row, health, destroyer in
        let (value) = row.fields
        if value.value < 0 {
            destroyer.destroy(row.entityID)
        } else {
            try health.set(ConcurrentHealth(value: value.value + 10), on: row.entityID)
        }
    }
    try await world.run(system, deltaTime: 0, parallelism: 2)
    #expect(keep[ConcurrentHealth.self]?.value == 11)
    #expect(!world.entityExists(doomed.id))
}

@Test func `dump prints without crashing`() {
    let world = World()
    world.createEntity(Position(x: 1, y: 2))
    world.dump()
    #expect(world.dumpString().contains("Position"))
}

@Test func `predicate operators flatten nested groups`() {
    let position = QueryPredicate.contains(Position.self)
    let velocity = QueryPredicate.contains(Velocity.self)
    let health = QueryPredicate.contains(Health.self)
    #expect(((position && velocity) && (health && position)) == .and([position, velocity, health, position]))
    #expect((position && (velocity && health)) == .and([position, velocity, health]))
    #expect(((position || velocity) || (health || position)) == .or([position, velocity, health, position]))
    #expect((position || (velocity || health)) == .or([position, velocity, health]))
}

@Test func `removed relationship observers stop receiving events`() throws {
    let world = World()
    var events: [RelationshipEvent] = []
    let token = world.observeRelationship(ChildOf.self) { events.append($0) }
    let parent = world.createEntity()
    let first = world.createEntity()
    let second = world.createEntity()
    try first.setParent(parent)
    world.removeObserver(token)
    try second.setParent(parent)
    #expect(events == [.added(source: first.id, target: parent.id)])
}

@Test func `dependencies on non-system entities are rejected`() throws {
    let world = World()
    let system = try world.addSystem(System("system").run { _ in })
    let stranger = world.createEntity()
    try system.addRelationship(DependsOn.self, to: stranger)
    let expected = SystemError.invalidDependency(source: system.id, target: stranger.id)
    #expect(throws: expected) { try world.update(deltaTime: 0) }
    #expect(expected.description.contains("Invalid scheduling dependency"))
}

private final class ReferenceComponent: Component {}

@Test func `system commands reject reference components`() throws {
    let world = World()
    let entity = world.createEntity()
    #expect(throws: SystemError.referenceComponent(ComponentType(ReferenceComponent.self))) {
        try world.run(System("set").run(Commands()) { _, commands in
            try commands.set(ReferenceComponent(), on: entity.id)
        }, deltaTime: 0)
    }
    #expect(throws: SystemError.referenceComponent(ComponentType(ReferenceComponent.self))) {
        try world.run(System("create").run(Commands()) { _, commands in
            try commands.create(ReferenceComponent())
        }, deltaTime: 0)
    }
}

@Test func `parallel component commands fail for destroyed targets`() async throws {
    let world = World()
    world.createEntity(ConcurrentHealth(value: 0))
    let missing = EntityID()
    let system = System("set").query(Read<ConcurrentHealth>()).eachParallel(EditComponent<ConcurrentHealth>()) { _, _, health in
        try health.set(ConcurrentHealth(value: 1), on: missing)
    }
    await #expect(throws: SystemError.missingCommandEntity(missing)) {
        try await world.run(system, deltaTime: 0, parallelism: 2)
    }
}

@Test func `removing a component from a non-last entity keeps the moved entity addressable`() {
    let world = World()
    let first = world.createEntity(Position(x: 1, y: 0), Health(current: 1))
    let second = world.createEntity(Position(x: 2, y: 0), Health(current: 2))
    #expect(first.remove(Health.self)?.current == 1)
    #expect(second[Health.self]?.current == 2)
    #expect(second[Position.self]?.x == 2)
    #expect(first[Position.self]?.x == 1)
}

@Test func `typed creation keeps the last value when a component is set twice`() {
    let world = World()
    let entity = world.createEntity(id: EntityID(), types: [ComponentType(Health.self)]) { initializer in
        initializer.set(Health(current: 1))
        initializer.set(Health(current: 2))
    }
    #expect(entity[Health.self]?.current == 2)
}
