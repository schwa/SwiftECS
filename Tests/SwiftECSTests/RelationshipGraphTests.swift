@testable import SwiftECS
import Testing

private enum Likes: Relationship {}

@Test func `forward and reverse indexes stay consistent across mixed edits`() throws {
    let world = World()
    let a = world.createEntity()
    let b = world.createEntity()
    let c = world.createEntity()
    // Non-exclusive links: a likes b and c.
    try a.addRelationship(Likes.self, to: b)
    try a.addRelationship(Likes.self, to: c)
    try c.addRelationship(Likes.self, to: b)
    #expect(a.targets(of: Likes.self).map(\.id) == [b.id, c.id])
    let sources: [EntityID] = b.sources(of: Likes.self).map(\.id).sorted()
    let expectedSources: [EntityID] = [a.id, c.id].sorted()
    #expect(sources == expectedSources)
    // Removing one link updates both directions.
    #expect(try a.removeRelationship(Likes.self, to: b))
    #expect(a.targets(of: Likes.self).map(\.id) == [c.id])
    #expect(b.sources(of: Likes.self).map(\.id) == [c.id])
    // Removing an absent link is a no-op and reports false.
    #expect(try a.removeRelationship(Likes.self, to: b) == false)
}

@Test func `distinct relationship types are isolated in the owner`() throws {
    let world = World()
    let parent = world.createEntity()
    let child = world.createEntity()
    try child.setParent(parent)
    try child.addRelationship(Likes.self, to: parent)
    #expect(child.parent?.id == parent.id)
    #expect(child.targets(of: Likes.self).map(\.id) == [parent.id])
    // Removing the Likes link leaves ChildOf intact.
    #expect(try child.removeRelationship(Likes.self, to: parent))
    #expect(child.parent?.id == parent.id)
    #expect(child.targets(of: Likes.self).isEmpty)
}

@Test func `deleting an entity clears its links in both directions across types`() throws {
    let world = World()
    let hub = world.createEntity()
    let a = world.createEntity()
    let b = world.createEntity()
    try a.setParent(hub)
    try b.addRelationship(Likes.self, to: hub)
    try hub.addRelationship(Likes.self, to: a)
    try world.destroy(hub)
    // Surviving entities have no dangling references to the deleted hub.
    #expect(a.parent == nil)
    #expect(b.targets(of: Likes.self).isEmpty)
    #expect(a.sources(of: Likes.self).isEmpty)
}

@Test func `cloning copies outgoing links only and preserves original targets`() throws {
    let world = World()
    let origin = world.createEntity()
    let friend = world.createEntity()
    let admirer = world.createEntity()
    try origin.addRelationship(Likes.self, to: friend)   // outgoing
    try admirer.addRelationship(Likes.self, to: origin)  // incoming to origin
    try origin.addRelationship(Likes.self, to: origin)   // self-link
    let clone = try #require(try world.clone(origin))
    let cloneTargets = Set(clone.targets(of: Likes.self).map(\.id))
    // Outgoing links copied, including the self-link retargeted to the original.
    #expect(cloneTargets == [friend.id, origin.id])
    // Incoming links are not copied.
    #expect(clone.sources(of: Likes.self).isEmpty)
    // The original is unchanged.
    #expect(Set(origin.targets(of: Likes.self).map(\.id)) == [friend.id, origin.id])
}

@Test func `acyclic policy still rejects cycles and preserves existing links after refactor`() throws {
    let world = World()
    let root = world.createEntity()
    let mid = world.createEntity()
    let leaf = world.createEntity()
    try mid.setParent(root)
    try leaf.setParent(mid)
    // A cycle (root under leaf) is rejected; existing links are preserved.
    #expect(throws: RelationshipError.cycleDetected(RelationshipType(ChildOf.self))) {
        try root.setParent(leaf)
    }
    #expect(mid.parent?.id == root.id)
    #expect(leaf.parent?.id == mid.id)
    #expect(root.parent == nil)
    // Descendant traversal order is unchanged (BFS, root-excluded).
    #expect(root.descendants().map(\.id) == [mid.id, leaf.id])
}
