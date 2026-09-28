@testable import SwiftECS
import Testing

private enum SyncFailure: Error { case callback }

@Test func `failed callbacks discard their commands but preserve earlier successful effects`() throws {
    let world = World()
    let position = world.createEntity(Position(x: 0, y: 0))
    var laterRan = false
    try world.addSystem(System("earlier").run(CreateEntities(Health.self)) { _, creator in try creator.create(Health(current: 1)) })
    try world.addSystem(System("failed").run(SystemQuery(Write<Position>()), CreateEntities(Position.self)) { _, rows, creator in
        for row in rows { row.fields.value.x = 10 }
        try creator.create(Position(x: 20, y: 0))
        #expect(world.snapshot(with: Health.self).isEmpty)
        throw SyncFailure.callback
    })
    try world.addSystem(System("later").run { _ in laterRan = true })
    #expect(throws: SyncFailure.self) { try world.update(deltaTime: 1) }
    #expect(position[Position.self]?.x == 10)
    #expect(world.snapshot(with: Position.self).count == 1)
    #expect(world.snapshot(with: Health.self).count == 1)
    #expect(!laterRan)
    #expect(world.reservedCommandIDs.isEmpty)
    #expect(world.lastRunStatistics.mergeCount == 1)
    #expect(world.lastRunStatistics.systemCount == 2)
}

@Test func `flush failures preserve the applied prefix and release discarded reservations`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    let missing = EntityID()
    try world.addSystem(System("first").run(EditComponent<Health>()) { _, health in try health.set(Health(current: 1), on: entity.id) })
    try world.addSystem(System("invalid").run(EditComponent<Health>()) { _, health in try health.set(Health(current: 2), on: missing) })
    try world.addSystem(System("create").run(CreateEntities(Position.self)) { _, creator in try creator.create(Position(x: 0, y: 0)) })
    #expect(throws: SystemError.missingCommandEntity(missing)) { try world.update(deltaTime: 0) }
    #expect(entity[Health.self]?.current == 1)
    #expect(world.snapshot(with: Position.self).isEmpty)
    #expect(world.reservedCommandIDs.isEmpty)
    #expect(world.lastRunStatistics.commandCount == 2)
    #expect(world.lastRunStatistics.mergeCount == 1)
}

@Test func `an earlier flush error takes precedence over a later callback error`() throws {
    let world = World()
    let missing = EntityID()
    try world.addSystem(System("pending").run(EditComponent<Health>()) { _, health in try health.set(Health(current: 1), on: missing) })
    try world.addSystem(System("throw").run { _ in throw SyncFailure.callback })
    #expect(throws: SystemError.missingCommandEntity(missing)) { try world.update(deltaTime: 0) }
    #expect(world.executions.isEmpty)
}

@Test func `nested runs see completed outer callbacks but not the active callbacks private commands`() throws {
    let world = World()
    let position = world.createEntity(Position(x: 0, y: 0))
    try world.addSystem(System("first").run(CreateEntities(Health.self)) { _, creator in try creator.create(Health(current: 1)) })
    try world.addSystem(System("nested").run(SystemQuery(Write<Position>()), CreateEntities(Position.self)) { _, rows, creator in
        let reference = try #require(rows.first { _ in true }).fields
        try creator.create(Position(x: 5, y: 0))
        try world.run(System("inner").query(Read<Health>()).run { _, health in
            #expect(health.count { _ in true } == 1)
            #expect(world.snapshot(with: Position.self).count == 1)
        }, deltaTime: 0)
        reference.value.x = 10
    })
    try world.update(deltaTime: 1)
    #expect(position[Position.self]?.x == 10)
    #expect(world.snapshot(with: Position.self).count == 2)
    #expect(world.lastRunStatistics.mergeCount == 2)
    #expect(world.executions.isEmpty)
    #expect(world.reservedCommandIDs.isEmpty)
}

@Test func `caught nested callback errors do not discard the outer callbacks private commands`() throws {
    let world = World()
    try world.addSystem(System("outer").run(CreateEntities(Health.self)) { _, creator in
        try creator.create(Health(current: 1))
        #expect(throws: SyncFailure.self) {
            try world.run(System("nested").run(CreateEntities(Position.self)) { _, inner in
                try inner.create(Position(x: 0, y: 0))
                throw SyncFailure.callback
            }, deltaTime: 0)
        }
        #expect(world.snapshot(with: Health.self).isEmpty)
    })
    try world.update(deltaTime: 1)
    #expect(world.snapshot(with: Health.self).count == 1)
    #expect(world.snapshot(with: Position.self).isEmpty)
    #expect(world.reservedCommandIDs.isEmpty)
    #expect(world.lastRunStatistics.mergeCount == 1)
}

@Test func `nested pipeline entities read their configuration after completed commands merge`() throws {
    let world = World()
    let pipeline = world.createEntity()
    try world.addSystem(System("configure").run(EditComponent<Pipeline>()) { _, components in
        try components.set(Pipeline(.none), on: pipeline.id)
    })
    try world.addSystem(System("nested").run { _ in
        try world.run(pipeline, deltaTime: 10)
        #expect(world.lastRunStatistics.systemCount == 0)
    })
    try world.update(deltaTime: 1)
    #expect(world.simulationTime == 1)
    #expect(world.lastRunStatistics.mergeCount == 1)
}

@Test func `reentrant observers drain the remaining commands before a nested run`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    var entries: [String] = []
    var nesting = false
    let token = world.observe(Health.self) { event in
        guard case let .changed(_, value) = event else { return }
        entries.append("event-\(value.current)")
        if !nesting {
            nesting = true
            do {
                try world.run(System("nested").query(Read<Health>()).each { _, health in
                    entries.append("nested-\(health.current)")
                }, deltaTime: 0)
            } catch {
                Issue.record(error)
            }
            entries.append("returned")
        }
    }
    defer { world.removeObserver(token) }
    try world.run(System("producer").run(EditComponent<Health>()) { _, health in
        try health.set(Health(current: 1), on: entity.id)
        try health.set(Health(current: 2), on: entity.id)
    }, deltaTime: 0)
    #expect(entries == ["event-1", "event-2", "nested-2", "returned"])
    #expect(world.lastRunStatistics.mergeCount == 1)
    #expect(world.lastRunStatistics.commandCount == 2)
}

@Test func `a caught reentrant flush failure still aborts the owning merge`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    let missing = EntityID()
    var caught = false
    let token = world.observe(Health.self) { _ in
        do {
            try world.run(System("nested").run { _ in Issue.record("Nested body ran after a failed merge") }, deltaTime: 0)
        } catch {
            caught = true
        }
    }
    let producer = System("producer").run(EditComponent<Health>()) { _, health in
        try health.set(Health(current: 1), on: entity.id)
        try health.set(Health(current: 2), on: missing)
        try health.set(Health(current: 3), on: entity.id)
    }
    #expect(throws: SystemError.missingCommandEntity(missing)) { try world.run(producer, deltaTime: 0) }
    #expect(caught)
    #expect(entity[Health.self]?.current == 1)
    #expect(world.executions.isEmpty)
    world.removeObserver(token)
    try world.run(System("recovery").run(EditComponent<Health>()) { _, health in try health.set(Health(current: 4), on: entity.id) }, deltaTime: 0)
    #expect(entity[Health.self]?.current == 4)
}

@Test func `system destruction retains the captured schedule and defers cleanup until the outermost run`() throws {
    let world = World()
    var entries: [String] = []
    var victim: EntityID?
    try world.addSystem(System("destroy").run(DestroyEntities()) { _, destroyer in destroyer.destroy(victim!) })
    victim = try world.addSystem(System("victim").run { _ in entries.append("run") }.onCleanup { entries.append("cleanup") }).id
    try world.update(deltaTime: 0)
    #expect(entries == ["run", "cleanup"])
    #expect(world.systemCount == 1)
    #expect(world.lastRunStatistics.mergeCount == 1)
}
