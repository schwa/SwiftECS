import ECS
import Observation
import Testing

// Observation callbacks run synchronously on the test thread.
private final class LifecycleChange: @unchecked Sendable {
    var changed = false
}

@Test func `world lifecycle methods reject foreign handles without changing either world`() throws {
    let owner = World()
    let other = World()
    let entity = owner.createEntity(Health(current: 10))
    let child = owner.createEntity()
    try child.setParent(entity)
    let ownerChange = LifecycleChange()
    let otherChange = LifecycleChange()
    withObservationTracking {
        _ = owner.entityCount
    } onChange: {
        ownerChange.changed = true
    }
    withObservationTracking {
        _ = other.entityCount
    } onChange: {
        otherChange.changed = true
    }
    #expect(!other.destroy(entity))
    #expect(other.clone(entity) == nil)
    #expect(other.destroyRecursively(entity) == 0)
    #expect(other.destroyRecursively(entity, following: ChildOf.self) == 0)
    #expect(owner.entityCount == 2)
    #expect(other.entityCount == 0)
    #expect(child.parent?.id == entity.id)
    #expect(!ownerChange.changed)
    #expect(!otherChange.changed)
}

@Test func `world lifecycle methods preserve handle identity and reject stale handles`() throws {
    let world = World()
    let original = world.createEntity(Health(current: 10))
    let clone = try #require(world.clone(original))
    #expect(clone.id != original.id)
    #expect(clone[Health.self]?.current == 10)
    #expect(world.destroy(original))
    #expect(!original.exists)
    #expect(clone.exists)
    let change = LifecycleChange()
    withObservationTracking {
        _ = world.entityCount
    } onChange: {
        change.changed = true
    }
    #expect(!world.destroy(original))
    #expect(world.clone(original) == nil)
    #expect(world.destroyRecursively(original) == 0)
    #expect(!change.changed)
}
