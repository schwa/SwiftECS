@testable import SwiftECS
import Testing

@Test func `empty matches skip each but still invoke run and tasks`() throws {
    let world = World()
    var calls = 0
    try world.run(System("each").query(Read<Health>()).each { _, _ in calls += 100 }, deltaTime: 1)
    try world.run(System("rows").query(Read<Health>()).run { context, rows in
        #expect(context.deltaTime == 2)
        #expect(rows.count { _ in true } == 0)
        calls += 1
    }, deltaTime: 2)
    try world.run(System("task").run { context in
        #expect(context.simulationTime == 0)
        calls += 1
    }, deltaTime: 3)
    #expect(calls == 2)
    #expect(world.systemCount == 0)
    #expect(world.simulationTime == 0)
}

@Test func `zero term queries iterate identities without granting component access`() throws {
    let world = World()
    let first = world.createEntity()
    let second = world.createEntity(Health(current: 1))
    var ids: Set<EntityID> = []
    let system = System("identities").query().run { _, rows in
        ids = Set(rows.map(\.entityID))
    }
    try world.run(system, deltaTime: 0)
    #expect(ids == [first.id, second.id])
    #expect(system.access.reads.isEmpty)
    #expect(system.access.writes.isEmpty)
}

@Test func `system filters include relationships and exclusions`() throws {
    let world = World()
    let parent = world.createEntity()
    let included = world.createEntity(Position(x: 0, y: 0))
    let excluded = world.createEntity(Position(x: 0, y: 0), Health(current: 1))
    let unrelated = world.createEntity(Position(x: 0, y: 0))
    try included.setParent(parent)
    try excluded.setParent(parent)
    let filter = Query(.related(ChildOf.self, to: parent.id)).without(Health.self)
    let system = System("filter").query(Write<Position>(), matching: filter).each { _, position in
        position.value.x += 1
    }
    try world.run(system, deltaTime: 0)
    #expect(included[Position.self]?.x == 1)
    #expect(excluded[Position.self]?.x == 0)
    #expect(unrelated[Position.self]?.x == 0)
    try included.setParent(nil)
    try world.run(system, deltaTime: 0)
    #expect(included[Position.self]?.x == 1)
}

@Test func `read values and unused write terms do not emit component changes`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 5), Position(x: 0, y: 0))
    var events = 0
    let healthToken = world.observe(Health.self) { _ in events += 1 }
    let positionToken = world.observe(Position.self) { _ in events += 1 }
    defer {
        world.removeObserver(healthToken)
        world.removeObserver(positionToken)
    }
    try world.run(System("read").query(Read<Health>(), Write<Position>()).each { _, health, position in
        var copy = health
        copy.current += 10
        #expect(copy.current == 15)
        #expect(position.value.x == 0)
    }, deltaTime: 0)
    #expect(entity[Health.self]?.current == 5)
    #expect(events == 0)
}

@Test func `successful callbacks invalidate every scoped input`() throws {
    let world = World()
    world.createEntity(Health(current: 1))
    var retainedRows: SystemRows<Write<Health>>?
    var retainedCommands: SystemCommands?
    try world.run(System("scope").run(SystemQuery(Write<Health>()), Commands()) { _, rows, commands in
        retainedRows = rows
        retainedCommands = commands
        let temporary = try commands.create()
        commands.destroy(temporary)
    }, deltaTime: 0)
    #expect(retainedRows?.scope.isActive == false)
    #expect(retainedCommands?.scope.isActive == false)
    #expect(retainedCommands?.scope.commands.isEmpty == true)
    #expect(world.entityCount == 1)
}

@Test func `command errors stop the pipeline and do not leave a live scope`() throws {
    let world = World()
    let first = world.createEntity()
    let second = world.createEntity()
    var retained: SystemCommands?
    var laterRan = false
    try world.addSystem(System("cycle").run(Commands()) { _, commands in
        retained = commands
        commands.addRelationship(ChildOf.self, from: first.id, to: second.id)
        commands.addRelationship(ChildOf.self, from: second.id, to: first.id)
        commands.destroy(first.id)
    })
    try world.addSystem(System("later").run { _ in laterRan = true })
    #expect(throws: RelationshipError.cycleDetected(RelationshipType(ChildOf.self))) {
        try world.update(deltaTime: 1)
    }
    #expect(first.exists)
    #expect(first.parent?.id == second.id)
    #expect(!laterRan)
    #expect(retained?.scope.isActive == false)
    #expect(retained?.scope.commands.isEmpty == true)
}

@Test func `observers can remove remaining rows without stale component access`() throws {
    let world = World()
    let first = world.createEntity(Health(current: 0))
    let second = world.createEntity(Health(current: 0))
    var events = 0
    let token = world.observe(Health.self) { _ in
        events += 1
        do {
            try world.destroy(first)
            try world.destroy(second)
        } catch {
            Issue.record(error)
        }
    }
    defer { world.removeObserver(token) }
    try world.run(System("remove").query(Write<Health>()).each { _, health in
        health.value.current = 1
    }, deltaTime: 0)
    #expect(events == 1)
    #expect(world.entityCount == 0)
}
