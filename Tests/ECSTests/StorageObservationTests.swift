import ECS
import Foundation
import Observation
import Testing

// Tests and observation callbacks execute synchronously on the same thread.
private final class StorageTracker: @unchecked Sendable {
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

private struct ObservationTestSystem: System {
    let action: (World) throws -> Void

    func update(world: World, deltaTime _: Double) {
        do {
            try action(world)
        } catch {
            Issue.record(error)
        }
    }
}

@Test func `every storage read observes component writes`() throws {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2))
    let query = Query(with: Position.self)
    world.register(query)
    let reference = try #require(world.references(query, Position.self).first { _ in true })
    let sequence = world.entities(matching: query)
    let fastSequence = world.references(query, Position.self)
    let reads: [() -> Void] = [
        { _ = entity[Position.self] },
        { _ = entity[Health.self] },
        { _ = entity.contains(Health.self) },
        { _ = entity.componentTypes },
        { _ = world.componentTypes(for: entity) },
        { _ = entity.allComponents },
        { _ = entity.exists },
        { _ = world[entity.id] },
        { _ = world.entityCount },
        { _ = world.entities },
        { _ = world.snapshot(matching: query) },
        { _ = world.snapshot(with: Position.self) },
        { _ = world.entities(matching: query) },
        { _ = world.references(query, Position.self) },
        { _ = Array(sequence) },
        { _ = Array(fastSequence) },
        { _ = reference[Position.self] },
        { _ = entity.get(Position.self) },
        { _ = world.stats },
        { _ = world.dumpString() },
        { _ = world.dumpDetailed() }
    ]
    for read in reads {
        let tracker = StorageTracker(read)
        entity.set(Position(x: 3, y: 4))
        #expect(tracker.count == 1)
        entity.set(Position(x: 5, y: 6))
        #expect(tracker.count == 2)
    }
}

@Test func `empty and missing results observe structural mutations`() throws {
    let world = World()
    let query = Query(with: Health.self)
    world.register(query)
    let tracker = StorageTracker {
        #expect(world.snapshot(matching: query).isEmpty || world.entityCount > 0)
        _ = world.entities(matching: query)
        _ = world.references(query, Health.self)
    }
    let entity = world.createEntity()
    #expect(tracker.count == 1)
    entity.set(Health(current: 10))
    #expect(tracker.count == 2)
    #expect(world.snapshot(matching: query).count == 1)
    entity.remove(Health.self)
    #expect(tracker.count == 3)
    #expect(world.snapshot(matching: query).isEmpty)
    let clone = try world.clone(entity)
    #expect(tracker.count == 4)
    if let clone {
        try world.destroy(clone)
    }
    #expect(tracker.count == 5)
    try world.destroy(entity)
    #expect(tracker.count == 6)
    let missing = StorageTracker {
        _ = entity.exists
        _ = world[entity.id]
        _ = entity[Position.self]
    }
    world.createEntity(Health(current: 1))
    #expect(missing.count == 1)
}

@Test func `each empty query path tracks future matches`() throws {
    for registered in [false, true] {
        let world = World()
        let query = Query(with: Health.self)
        if registered {
            world.register(query)
        }
        let reads: [() -> Void] = [
            { _ = world.snapshot(matching: query) },
            { _ = world.snapshot(with: Health.self) },
            { _ = world.entities(matching: query) },
            { _ = world.references(query, Health.self) },
            { _ = Array(world.entities(matching: query)) },
            { _ = Array(world.references(query, Health.self)) }
        ]
        for read in reads {
            let tracker = StorageTracker(read)
            let entity = world.createEntity(Health(current: 1))
            #expect(tracker.count == 1)
            try world.destroy(entity)
            #expect(tracker.count == 2)
        }
    }
}

@Test func `empty retained iterators register access even when exhausted`() {
    let world = World()
    var ordinary = world.entities(matching: .all).makeIterator()
    var fast = world.references(.all, Health.self).makeIterator()
    let ordinaryTracker = StorageTracker { _ = ordinary.next() }
    let fastTracker = StorageTracker { _ = fast.next() }
    world.createEntity(Health(current: 1))
    #expect(ordinaryTracker.count == 1)
    #expect(fastTracker.count == 1)
}

@Test func `fast reference writes notify and preserve component events`() throws {
    let world = World()
    world.createEntity(Position(x: 0, y: 0))
    let reference = try #require(world.references(Query(with: Position.self), Position.self).first { _ in true })
    let tracker = StorageTracker { _ = reference[Position.self] }
    var events = 0
    let token = world.observe(Position.self) { _ in events += 1 }
    reference[Position.self] = Position(x: 10, y: 20)
    #expect(tracker.count == 1)
    #expect(events == 1)
    #expect(reference[Position.self].x == 10)
    world.removeObserver(token)
}

@Test func `failed mutations and other worlds do not invalidate storage`() throws {
    let world = World()
    let entity = world.createEntity()
    try world.destroy(entity)
    let tracker = StorageTracker { _ = world.entityCount }
    entity.set(Health(current: 1))
    entity.remove(Health.self)
    try world.destroy(entity)
    _ = try world.clone(entity)
    let other = World()
    let live = other.createEntity()
    live.set(Health(current: 1))
    #expect(tracker.count == 0)
    let empty = world.createEntity()
    #expect(tracker.count == 1)
    empty.remove(Health.self)
    #expect(tracker.count == 1)
}

@Test func `ten thousand writes emit one storage notification per update`() throws {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0))
    let tracker = StorageTracker { _ = entity[Position.self] }
    let reference = try #require(world.references(Query(with: Position.self), Position.self).first { _ in true })
    try world.addSystem(ObservationTestSystem { world in
        let before = tracker.count
        for index in 0..<10_000 {
            if index.isMultiple(of: 2) {
                entity.set(Position(x: Double(index), y: 0))
            } else {
                reference[Position.self] = Position(x: Double(index), y: 0)
            }
        }
        let temporary = world.createEntity(Health(current: 1))
        temporary.remove(Health.self)
        try world.destroy(temporary)
        #expect(tracker.count == before)
    })
    try world.update(deltaTime: 1)
    #expect(tracker.count == 1)
    #expect(entity[Position.self]?.x == 9_999)
    try world.update(deltaTime: 1)
    #expect(tracker.count == 2)
    entity.set(Position(x: 0, y: 0))
    #expect(tracker.count == 3)
}

@Test func `updates without storage writes only notify simulation time`() throws {
    let world = World()
    let storage = StorageTracker { _ = world.entityCount }
    let time = StorageTracker { _ = world.simulationTime }
    try world.update(deltaTime: 1)
    #expect(storage.count == 0)
    #expect(time.count == 1)
}

@Test func `nested updates flush only when outer update completes`() throws {
    let world = World()
    let tracker = StorageTracker { _ = world.entityCount }
    var nested = false
    try world.addSystem(ObservationTestSystem { world in
        world.createEntity()
        if !nested {
            nested = true
            do {
                try world.update(deltaTime: 0)
            } catch {
                Issue.record(error)
            }
            nested = false
        }
        #expect(tracker.count == 0)
    })
    try world.update(deltaTime: 1)
    #expect(tracker.count == 1)
    #expect(world.entityCount == 2)
}

@Test func `failed nested update preserves pending invalidation and future writes`() throws {
    let world = World()
    let tracker = StorageTracker { _ = world.entityCount }
    try world.addSystem(ObservationTestSystem { world in
        world.createEntity()
        do {
            try world.addSystem(ObservationTestSystem { _ in }, id: "broken", dependencies: ["missing"])
            try world.update(deltaTime: 0)
            Issue.record("Expected missing dependency failure")
        } catch {
            #expect(error as? SystemError == .dependencyNotFound(system: "broken", dependency: "missing"))
        }
        #expect(tracker.count == 0)
    })
    try world.update(deltaTime: 1)
    #expect(tracker.count == 1)
    #expect(throws: SystemError.self) { try world.update(deltaTime: 1) }
    #expect(tracker.count == 1)
    world.createEntity()
    #expect(tracker.count == 2)
    world.removeAllSystems()
    try world.update(deltaTime: 1)
    #expect(tracker.count == 2)
}
