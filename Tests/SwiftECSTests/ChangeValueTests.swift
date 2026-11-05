import SwiftECS
import Testing

private struct Level: Component, Equatable {
    var value: Int
}

private struct Other: Component {
    var value: Int
}

// The handler runs synchronously on the test's thread.
private final class Changes: @unchecked Sendable {
    var pairs: [[Int]] = []
}

// #48
@Test
func changeObserversGetOldAndNewValues() throws {
    let world = World()
    let entity = world.createEntity(Level(value: 1), Other(value: 0))
    let changes = Changes()
    let token = world.observeChanges(Level.self) { change in
        #expect(change.entity.id == entity.id)
        changes.pairs.append([change.oldValue.value, change.newValue.value])
    }

    entity.set(Level(value: 2))
    try #require(world.componentRef(Level.self, for: entity.id)).value = Level(value: 3)
    for row in world.query(Level.self, Other.self) {
        row.set(Level(value: 4), Other(value: 1))
    }
    #expect(changes.pairs == [[1, 2], [2, 3], [3, 4]])

    world.removeObserver(token)
    entity.set(Level(value: 5))
    #expect(changes.pairs.count == 3)
}

@Test
func changeObserversSeeSystemWrites() throws {
    let world = World()
    world.createEntity(Level(value: 1))
    let changes = Changes()
    world.observeChanges(Level.self) { change in
        changes.pairs.append([change.oldValue.value, change.newValue.value])
    }
    let raise = System("raise")
        .query(Write<Level>())
        .each { _, level in
            level.value = Level(value: level.value.value + 10)
        }
    try world.run(raise, deltaTime: 0)
    #expect(changes.pairs == [[1, 11]])
}

@Test
func changeObserversAreNotCalledForAdditions() {
    let world = World()
    let entity = world.createEntity(Other(value: 0))
    let changes = Changes()
    world.observeChanges(Level.self) { change in
        changes.pairs.append([change.oldValue.value, change.newValue.value])
    }
    entity.set(Level(value: 1))
    #expect(changes.pairs.isEmpty)
}
