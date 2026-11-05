import SwiftECS
import Testing

private struct LifecycleValue: Component {
    var value: Int
}

private enum Likes: Relationship {}

// The handlers run synchronously on the test's thread.
private final class Recorder<Event>: @unchecked Sendable {
    var events: [Event] = []
}

// #47
@Test
func destroyingAnEntityNotifiesDestroyObservers() throws {
    let world = World()
    let entity = world.createEntity(LifecycleValue(value: 1))
    let recorder = Recorder<EntityID>()
    let token = world.observeDestroyed { recorder.events.append($0) }
    _ = try world.destroy(entity)
    #expect(recorder.events == [entity.id])
    // Component observers still get no synthesized events on destroy.
    let other = world.createEntity(LifecycleValue(value: 2))
    world.removeObserver(token)
    _ = try world.destroy(other)
    #expect(recorder.events == [entity.id])
}

@Test
func relationshipChangesNotifyRelationshipObservers() throws {
    let world = World()
    let parent = world.createEntity()
    let otherParent = world.createEntity()
    let child = world.createEntity()
    let recorder = Recorder<RelationshipEvent>()
    world.observeRelationship(ChildOf.self) { recorder.events.append($0) }
    let likes = Recorder<RelationshipEvent>()
    world.observeRelationship(Likes.self) { likes.events.append($0) }

    try child.setParent(parent)
    // ChildOf is exclusive: the old edge is removed, then the new one added.
    try child.setParent(otherParent)
    try child.setParent(nil)
    #expect(recorder.events == [
        .added(source: child.id, target: parent.id),
        .removed(source: child.id, target: parent.id),
        .added(source: child.id, target: otherParent.id),
        .removed(source: child.id, target: otherParent.id)
    ])

    try child.addRelationship(Likes.self, to: parent)
    _ = try child.removeRelationship(Likes.self, to: parent)
    #expect(likes.events == [.added(source: child.id, target: parent.id), .removed(source: child.id, target: parent.id)])
    #expect(recorder.events.count == 4)
}
