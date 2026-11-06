import Observation
import SwiftECS
import Testing

private struct StableValue: Component {
    var x: Int
}

private struct StableTag: Component {}

// The onChange callback runs synchronously on the test's thread.
private final class ChangeCount: @unchecked Sendable {
    var value = 0
}

@Test
func createEntityWithChosenID() {
    let world = World()
    let id = EntityID()
    world.createEntity(id: id, StableValue(x: 1))
    #expect(world[id]?[StableValue.self]?.x == 1)
}

@Test
func createEntityFromRuntimeComponents() throws {
    let world = World()
    let id = EntityID()
    let components: [any Component] = [StableValue(x: 4), StableTag()]
    world.createEntity(id: id, components: components)
    let entity = try #require(world[id])
    #expect(entity[StableValue.self]?.x == 4)
    #expect(entity.contains(StableTag.self))
    #expect(world.snapshot(with: StableValue.self, StableTag.self).map(\.id) == [id])
}

@Test
func createEntityWithTypedInitializer() throws {
    let world = World()
    let types = [ComponentType(StableValue.self), ComponentType(StableTag.self)]
    let first = EntityID()
    let second = EntityID()
    world.createEntity(id: first, types: types) { initializer in
        initializer.set(StableValue(x: 1))
        initializer.set(StableTag())
    }
    world.createEntity(id: second, types: types) { initializer in
        initializer.set(StableTag())
        initializer.set(StableValue(x: 2))
    }
    #expect(world[first]?[StableValue.self]?.x == 1)
    #expect(world[second]?[StableValue.self]?.x == 2)
    #expect(Set(world.snapshot(with: StableValue.self, StableTag.self).map(\.id)) == [first, second])
    _ = try world.destroy(try #require(world[first]))
    #expect(world[second]?[StableValue.self]?.x == 2)
}

@Test
func componentRefReadsAndWritesTheEntity() throws {
    let world = World()
    let entity = world.createEntity(StableValue(x: 1))
    let ref = try #require(world.componentRef(StableValue.self, for: entity.id))
    ref.value.x = 5
    #expect(entity[StableValue.self]?.x == 5)
    #expect(world.componentRef(StableTag.self, for: entity.id) == nil)
}

@Test
func untrackedValueDoesNotObserveTheWorld() throws {
    let world = World()
    let entity = world.createEntity(StableValue(x: 1))
    let ref = try #require(world.componentRef(StableValue.self, for: entity.id))
    let changes = ChangeCount()
    withObservationTracking {
        #expect(ref.untrackedValue.x == 1)
    } onChange: {
        changes.value += 1
    }
    ref.value.x = 2
    #expect(changes.value == 0)
    #expect(ref.untrackedValue.x == 2)
}

@Test
func storageLocationChangesOnlyWhenTheEntityMoves() throws {
    let world = World()
    let first = world.createEntity(StableValue(x: 1))
    let second = world.createEntity(StableValue(x: 2))
    let location = try #require(world.storageLocation(of: second.id))
    // Other entities coming and going elsewhere leave it in place.
    let other = world.createEntity(StableTag())
    _ = try world.destroy(other)
    #expect(world.storageLocation(of: second.id) == location)
    // Swap-removing the entity before it moves it into the hole.
    _ = try world.destroy(first)
    #expect(world.storageLocation(of: second.id) != location)
    let moved = try #require(world.storageLocation(of: second.id))
    // Gaining a component moves it to another archetype.
    second.set(StableTag())
    #expect(world.storageLocation(of: second.id) != moved)
    _ = try world.destroy(second)
    #expect(world.storageLocation(of: second.id) == nil)
}

@Test
func structuralRevisionChangesOnlyOnStructuralChanges() {
    let world = World()
    let first = world.createEntity(StableValue(x: 1))
    let revision = world.structuralRevision
    first.set(StableValue(x: 2))
    #expect(world.structuralRevision == revision)
    first.set(StableTag())
    #expect(world.structuralRevision != revision)
    let afterAdd = world.structuralRevision
    world.createEntity(StableValue(x: 3))
    #expect(world.structuralRevision != afterAdd)
    let afterCreate = world.structuralRevision
    _ = try? world.destroy(first)
    #expect(world.structuralRevision != afterCreate)
}
