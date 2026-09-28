@testable import SwiftECS
import Testing

@Test(arguments: [PipelineSynchronization.automatic, .afterEachSystem])
func `independent producers merge together before a dependent reader`(policy: PipelineSynchronization) throws {
    let world = World()
    world.createEntity(Position(x: 0, y: 0))
    var order: [String] = []
    var retained: EntityCreator<Health>?
    try world.addSystem(System("first").run(CreateEntities(Health.self)) { _, creator in
        order.append("first")
        retained = creator
        try creator.create(Health(current: 1))
    })
    try world.addSystem(System("unrelated").query(Read<Position>()).each { _, _ in
        order.append("unrelated")
        #expect(retained?.scope.isActive == false)
        #expect(world.snapshot(with: Health.self).count == (policy == .automatic ? 0 : 1))
    })
    try world.addSystem(System("second").run(CreateEntities(Health.self)) { _, creator in
        order.append("second")
        try creator.create(Health(current: 2))
    })
    var values: [Int] = []
    try world.addSystem(System("reader").query(Read<Health>()).run { _, rows in
        order.append("reader")
        values = rows.map(\.fields.current).sorted()
    })
    try world.run(Pipeline(synchronization: policy), deltaTime: 1)
    #expect(order == ["first", "unrelated", "second", "reader"])
    #expect(values == [1, 2])
    #expect(world.lastRunStatistics.mergeCount == (policy == .automatic ? 1 : 2))
    #expect(world.lastRunStatistics.commandCount == 2)
    #expect(world.lastRunStatistics.systemCount == 4)
    #expect(world.simulationTime == 0)
}

@Test func `separate creation signatures do not satisfy a combined query`() throws {
    let world = World()
    try world.addSystem(System("position").run(CreateEntities(Position.self)) { _, creator in
        try creator.create(Position(x: 0, y: 0))
    })
    try world.addSystem(System("velocity").run(CreateEntities(Velocity.self)) { _, creator in
        try creator.create(Velocity(dx: 0, dy: 0))
    })
    try world.addSystem(System("both").query(Read<Position>(), Read<Velocity>()).run { _, rows in
        #expect(rows.count { _ in true } == 0)
        #expect(world.snapshot(with: Position.self).isEmpty)
        #expect(world.snapshot(with: Velocity.self).isEmpty)
    })
    try world.update(deltaTime: 1)
    #expect(world.snapshot(with: Position.self).count == 1)
    #expect(world.snapshot(with: Velocity.self).count == 1)
    #expect(world.lastRunStatistics.mergeCount == 1)
}

private struct SyncDisabled: Component {}

@Test func `exclusion predicates see deferred component edits before binding`() throws {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0))
    try world.addSystem(System("disable").run(EditComponent<SyncDisabled>()) { _, components in
        try components.set(SyncDisabled(), on: entity.id)
    })
    try world.addSystem(System("read").query(Read<Position>(), matching: Query.all.without(SyncDisabled.self)).each { _, _ in
        Issue.record("Disabled entity entered the query")
    })
    try world.update(deltaTime: 0)
    #expect(entity.contains(SyncDisabled.self))
    #expect(world.lastRunStatistics.mergeCount == 1)
}

@Test func `empty creations affect zero term and negated queries`() throws {
    let world = World()
    var created: EntityID?
    try world.addSystem(System("create").run(CreateEntities()) { _, creator in created = try creator.create() })
    try world.addSystem(System("none").query(matching: .none).run { _, rows in
        #expect(rows.count { _ in true } == 0)
        #expect(world[created!] == nil)
    })
    try world.addSystem(System("negative").query(matching: Query.all.without(Health.self)).run { _, rows in
        #expect(rows.contains { $0.entityID == created })
    })
    try world.update(deltaTime: 0)
    #expect(world.lastRunStatistics.mergeCount == 1)
}

@Test func `relationship traversal observes changes beyond the direct source`() throws {
    let world = World()
    let root = world.createEntity()
    let branch = world.createEntity()
    let leaf = world.createEntity(Health(current: 1))
    try leaf.setParent(branch)
    try world.addSystem(System("link").run(EditRelationship<ChildOf>()) { _, links in links.add(from: branch.id, to: root.id) })
    var descendants: [EntityID] = []
    try world.addSystem(System("read").query(Read<Health>(), matching: Query(.descendant(of: root.id))).run { _, rows in
        descendants = rows.map(\.entityID)
    })
    try world.update(deltaTime: 0)
    #expect(descendants == [leaf.id])
    #expect(world.lastRunStatistics.mergeCount == 1)
}

@Test func `deferred writes precede immediate writes and queued writes preserve order`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    try world.addSystem(System("first").run(EditComponent<Health>()) { _, health in try health.set(Health(current: 1), on: entity.id) })
    try world.addSystem(System("second").run(EditComponent<Health>()) { _, health in try health.set(Health(current: 2), on: entity.id) })
    try world.addSystem(System("immediate").query(Write<Health>()).each { _, health in
        #expect(health.value.current == 2)
        health.value.current += 1
    })
    try world.addSystem(System("last").run(EditComponent<Health>()) { _, health in try health.set(Health(current: 4), on: entity.id) })
    try world.update(deltaTime: 0)
    #expect(entity[Health.self]?.current == 4)
    #expect(world.lastRunStatistics.mergeCount == 2)
}

@Test func `unused command capabilities and immediate writes do not create merges`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    try world.addSystem(System("unused").run(CreateEntities(Health.self)) { _, _ in })
    try world.addSystem(System("write").query(Write<Health>()).each { _, health in health.value.current += 1 })
    try world.addSystem(System("read").query(Read<Health>()).each { _, health in #expect(health.current == 1) })
    try world.update(deltaTime: 0)
    #expect(entity[Health.self]?.current == 1)
    #expect(world.lastRunStatistics.mergeCount == 0)
    #expect(world.lastRunStatistics.commandCount == 0)
    try world.run(Pipeline(.none), deltaTime: 0)
    #expect(world.lastRunStatistics.systemCount == 0)
    #expect(world.lastRunStatistics.mergeCount == 0)
}

@Test func `unrestricted commands and destruction retain conservative barriers`() throws {
    let world = World()
    let parent = world.createEntity()
    let child = world.createEntity()
    try child.setParent(parent)
    try world.addSystem(System("destroy").run(DestroyEntities()) { _, destroyer in destroyer.destroy(parent.id) })
    try world.addSystem(System("unrestricted").run(Commands()) { _, commands in
        #expect(!parent.exists)
        #expect(child.parent == nil)
        try commands.create(Health(current: 1))
    })
    try world.addSystem(System("task").run { _ in #expect(world.snapshot(with: Health.self).count == 1) })
    try world.update(deltaTime: 0)
    #expect(world.lastRunStatistics.mergeCount == 2)
}

@Test func `observers with undeclared side effects retain per system visibility`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 0))
    let token = world.observe(Health.self) { _ in world.createEntity(Position(x: 1, y: 0)) }
    defer { world.removeObserver(token) }
    for name in ["first", "second"] {
        try world.addSystem(System(SystemID(name)).run(EditComponent<Health>()) { _, health in try health.set(Health(current: 1), on: entity.id) })
    }
    var count = 0
    try world.addSystem(System("read").query(Read<Position>()).each { _, _ in count += 1 })
    try world.update(deltaTime: 0)
    #expect(count == 2)
    #expect(world.lastRunStatistics.mergeCount == 2)
}
