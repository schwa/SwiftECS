import ECS
import Observation
import Testing

private enum Targets: Relationship {}

@Test func `all query APIs filter relationships and cached queries see reparenting`() throws {
    let world = World()
    let firstParent = world.createEntity()
    let secondParent = world.createEntity()
    let first = world.createEntity(Health(current: 1))
    let second = world.createEntity(Health(current: 2))
    let query = Query(.contains(Health.self) && .related(ChildOf.self, to: firstParent.id))
    world.register(query)
    let lazy = world.entities(matching: query)
    let typed = world.query(Health.self, matching: query)
    #expect(world.snapshot(matching: query).isEmpty)
    try first.setParent(firstParent)
    try second.setParent(secondParent)
    #expect(world.snapshot(matching: query).map(\.id) == [first.id])
    #expect(Array(lazy).map(\.id) == [first.id])
    #expect(Array(typed).map(\.entityID) == [first.id])
    try first.setParent(secondParent)
    try second.setParent(firstParent)
    #expect(world.snapshot(matching: query).map(\.id) == [second.id])
    #expect(Array(lazy).map(\.id) == [second.id])
    #expect(Array(typed).map(\.entityID) == [second.id])
    for row in typed {
        row.set(Health(current: 10))
    }
    #expect(second[Health.self]?.current == 10)
    try world.destroy(firstParent)
    #expect(world.snapshot(matching: query).isEmpty)
    #expect(Array(typed).isEmpty)
}

@Test func `registered relationship queries discover new component archetypes`() throws {
    let world = World()
    let root = world.createEntity()
    let query = Query(.contains(Health.self) && .related(ChildOf.self))
    world.register(query)
    #expect(world.entities(matching: query).map(\.id).isEmpty)
    let child = world.createEntity(Health(current: 1), Position(x: 0, y: 0))
    try child.setParent(root)
    #expect(world.entities(matching: query).map(\.id) == [child.id])
    #expect(world.query(Health.self, matching: query).map(\.entityID) == [child.id])
    child.remove(Health.self)
    #expect(world.snapshot(matching: query).isEmpty)
    #expect(child.parent?.id == root.id)
}

@Test func `descendant predicates follow transitive links and exclude their root`() throws {
    let world = World()
    let root = world.createEntity(Health(current: 0))
    let child = world.createEntity(Health(current: 1))
    let leaf = world.createEntity(Health(current: 2))
    try child.setParent(root)
    try leaf.setParent(child)
    let query = Query(.descendant(of: root.id))
    world.register(query)
    #expect(Set(world.snapshot(matching: query).map(\.id)) == [child.id, leaf.id])
    #expect(Set(world.query(Health.self, matching: query).map(\.entityID)) == [child.id, leaf.id])
    try child.setParent(nil)
    #expect(world.snapshot(matching: query).isEmpty)
    try child.addRelationship(Targets.self, to: root)
    try leaf.addRelationship(Targets.self, to: child)
    try root.addRelationship(Targets.self, to: leaf)
    let cyclicQuery = Query(.descendant(of: root.id, via: Targets.self))
    #expect(Set(world.snapshot(matching: cyclicQuery).map(\.id)) == [child.id, leaf.id])
    #expect(world.snapshot(matching: Query(.related(Targets.self))).count == 3)
}

// Tests and tracking callbacks run synchronously on one thread.
private final class RelationshipQueryTracker: @unchecked Sendable {
    var notifications = 0
    let read: () -> Void

    init(_ read: @escaping () -> Void) {
        self.read = read
        observe()
    }

    private func observe() {
        withObservationTracking(read) { [weak self] in
            guard let self else {
                return
            }
            notifications += 1
            observe()
        }
    }
}

private struct ReparentSystem: System {
    let parent: Entity
    let child: Entity

    func update(world _: World, deltaTime _: Double) {
        do {
            try child.setParent(parent)
            try child.setParent(nil)
            try child.setParent(parent)
        } catch {
            Issue.record(error)
        }
    }
}

@Test func `empty relationship queries observe links and system mutations batch once`() throws {
    let world = World()
    let parent = world.createEntity()
    let child = world.createEntity(Health(current: 1))
    let query = Query(.related(ChildOf.self, to: parent.id))
    let reads: [() -> Void] = [
        { _ = world.snapshot(matching: query) },
        { _ = world.entities(matching: query) },
        { _ = world.query(Health.self, matching: query) }
    ]
    for read in reads {
        let tracker = RelationshipQueryTracker(read)
        try child.setParent(parent)
        #expect(tracker.notifications == 1)
        try child.setParent(nil)
        #expect(tracker.notifications == 2)
    }
    try world.addSystem(ReparentSystem(parent: parent, child: child))
    let tracker = RelationshipQueryTracker { _ = child.parent }
    try world.update(deltaTime: 1)
    #expect(tracker.notifications == 1)
    #expect(child.parent?.id == parent.id)
}
