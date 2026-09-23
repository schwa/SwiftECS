import ECS
import Observation
import Testing

private enum Likes: Relationship {}
private enum Follows: Relationship {}
private enum Dependency: Relationship {
    static var isAcyclic: Bool { true }
}
private enum Selected: Relationship {
    static var isExclusive: Bool { true }
}

// Tracking callbacks and these tests run synchronously on the same thread.
private final class RelationshipChanges: @unchecked Sendable {
    var count = 0
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
            count += 1
            observe()
        }
    }
}

@Test func `general pairs support multiple targets and distinct relationship types`() throws {
    let world = World()
    let source = world.createEntity()
    let first = world.createEntity()
    let second = world.createEntity()
    try source.addRelationship(Likes.self, to: first)
    try source.addRelationship(Likes.self, to: second)
    try source.addRelationship(Follows.self, to: first)
    try source.addRelationship(Likes.self, to: first)
    #expect(source.targets(of: Likes.self).map(\.id) == [first.id, second.id])
    #expect(first.sources(of: Likes.self).map(\.id) == [source.id])
    #expect(source.hasRelationship(Follows.self, to: first))
    #expect(try source.removeRelationship(Likes.self, to: first))
    #expect(!source.hasRelationship(Likes.self, to: first))
    #expect(source.hasRelationship(Follows.self, to: first))
    #expect(!(try source.removeRelationship(Likes.self, to: first)))
    #expect(world.stats.archetypeCount == 1)
}

@Test func `ChildOf is exclusive and cyclic reparenting leaves links unchanged`() throws {
    let world = World()
    let root = world.createEntity()
    let child = world.createEntity()
    let leaf = world.createEntity()
    try child.setParent(root)
    try leaf.setParent(child)
    #expect(leaf.ancestors().map(\.id) == [child.id, root.id])
    #expect(root.descendants().map(\.id) == [child.id, leaf.id])
    #expect(throws: RelationshipError.cycleDetected(RelationshipType(ChildOf.self))) {
        try root.setParent(leaf)
    }
    #expect(root.parent == nil)
    #expect(child.parent?.id == root.id)
    #expect(throws: RelationshipError.self) { try child.setParent(child) }
    try leaf.setParent(root)
    #expect(child.children.isEmpty)
    #expect(root.children.map(\.id) == [child.id, leaf.id])
    try leaf.setParent(nil)
    #expect(leaf.parent == nil)
}

@Test func `deleting a parent detaches children but recursive deletion removes its subtree`() throws {
    let world = World()
    let root = world.createEntity()
    let child = world.createEntity()
    let leaf = world.createEntity()
    let outside = world.createEntity()
    try child.setParent(root)
    try leaf.setParent(child)
    try outside.addRelationship(Likes.self, to: child)
    try world.destroy(root)
    #expect(child.exists)
    #expect(child.parent == nil)
    #expect(leaf.parent?.id == child.id)
    let changes = RelationshipChanges { _ = world.entityCount }
    #expect(try world.destroyRecursively(child) == 2)
    #expect(changes.count == 1)
    #expect(outside.exists)
    #expect(outside.targets(of: Likes.self).isEmpty)
    #expect(try world.destroyRecursively(child) == 0)
}

@Test func `general traversal visits cycles and diamonds once in breadth first order`() throws {
    let world = World()
    let root = world.createEntity()
    let first = world.createEntity()
    let second = world.createEntity()
    let leaf = world.createEntity()
    try first.addRelationship(Likes.self, to: root)
    try second.addRelationship(Likes.self, to: root)
    try leaf.addRelationship(Likes.self, to: first)
    try leaf.addRelationship(Likes.self, to: second)
    try root.addRelationship(Likes.self, to: leaf)
    #expect(root.descendants(via: Likes.self).map(\.id) == [first.id, second.id, leaf.id])
    #expect(try world.destroyRecursively(root, following: Likes.self) == 4)
    #expect(world.entityCount == 0)
}

@Test func `relationship writes reject dead and foreign entities`() throws {
    let world = World()
    let source = world.createEntity()
    let dead = world.createEntity()
    try world.destroy(dead)
    let foreign = World().createEntity()
    #expect(throws: RelationshipError.differentWorlds) { try source.setParent(foreign) }
    #expect(throws: RelationshipError.missingEntity(dead.id)) { try source.setParent(dead) }
    #expect(throws: RelationshipError.missingEntity(dead.id)) { try dead.setParent(source) }
    #expect(throws: RelationshipError.missingEntity(dead.id)) { try dead.setParent(nil) }
    #expect(!source.hasRelationship(ChildOf.self, to: foreign))
    #expect(source.targets(of: ChildOf.self).isEmpty)
}

@Test func `relationship reads observe writes and deletion without duplicate notifications`() throws {
    let world = World()
    let source = world.createEntity()
    let target = world.createEntity()
    let reads: [() -> Void] = [
        { _ = source.parent },
        { _ = target.children },
        { _ = source.targets(of: Likes.self) },
        { _ = target.sources(of: Likes.self) },
        { _ = source.hasRelationship(Likes.self, to: target) },
        { _ = source.ancestors() },
        { _ = target.descendants() }
    ]
    for read in reads {
        let changes = RelationshipChanges(read)
        try source.addRelationship(Likes.self, to: target)
        #expect(changes.count == 1)
        try source.addRelationship(Likes.self, to: target)
        #expect(changes.count == 1)
        try source.removeRelationship(Likes.self, to: target)
        #expect(changes.count == 2)
    }
    try source.setParent(target)
    let changes = RelationshipChanges { _ = source.parent }
    try world.destroy(target)
    #expect(changes.count == 1)
    #expect(source.parent == nil)
}

@Test func `exclusivity and cycle restrictions are independent policies`() throws {
    let world = World()
    let first = world.createEntity()
    let second = world.createEntity()
    let third = world.createEntity()
    try first.addRelationship(Dependency.self, to: second)
    try first.addRelationship(Dependency.self, to: third)
    #expect(first.targets(of: Dependency.self).count == 2)
    #expect(throws: RelationshipError.self) { try second.addRelationship(Dependency.self, to: first) }
    try first.addRelationship(Selected.self, to: second)
    try first.addRelationship(Selected.self, to: third)
    try third.addRelationship(Selected.self, to: first)
    #expect(first.targets(of: Selected.self).map(\.id) == [third.id])
    #expect(second.sources(of: Selected.self).isEmpty)
    try first.addRelationship(Likes.self, to: first)
    try world.destroy(first)
    #expect(third.targets(of: Selected.self).isEmpty)
}

@Test func `failed and duplicate relationship writes do not invalidate observation`() throws {
    let world = World()
    let root = world.createEntity()
    let child = world.createEntity()
    try child.setParent(root)
    let changes = RelationshipChanges { _ = root.children }
    #expect(throws: RelationshipError.self) { try root.setParent(child) }
    try child.setParent(root)
    try root.setParent(nil)
    #expect(!(try root.removeRelationship(Likes.self, to: child)))
    #expect(changes.count == 0)
    let otherWorld = World()
    let otherParent = otherWorld.createEntity()
    let otherChild = otherWorld.createEntity()
    try otherChild.setParent(otherParent)
    #expect(changes.count == 0)
}

@Test func `deep hierarchy traversal and recursive deletion use iterative walks`() throws {
    let world = World()
    let root = world.createEntity()
    var parent = root
    for _ in 0..<200 {
        let child = world.createEntity()
        try child.setParent(parent)
        parent = child
    }
    #expect(root.descendants().count == 200)
    #expect(parent.ancestors().count == 200)
    #expect(try world.destroyRecursively(root) == 201)
    #expect(world.entityCount == 0)
}

@Test func `cloning copies outgoing pairs without copying descendants`() throws {
    let world = World()
    let parent = world.createEntity()
    let source = world.createEntity(Health(current: 5))
    let child = world.createEntity()
    try source.setParent(parent)
    try child.setParent(source)
    try source.addRelationship(Likes.self, to: child)
    let clone = try #require(try world.clone(source))
    #expect(clone.parent?.id == parent.id)
    #expect(clone.children.isEmpty)
    #expect(clone.hasRelationship(Likes.self, to: child))
    try world.destroy(clone)
    #expect(source.parent?.id == parent.id)
    #expect(child.parent?.id == source.id)
}
