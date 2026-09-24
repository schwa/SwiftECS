import SwiftECS
import Testing

@Test func `observer removal preserves other subscribers and allows registration again`() {
    let world = World()
    let entity = world.createEntity()
    var firstChanges = 0
    var secondChanges = 0
    var healthChanges = 0
    let first = world.observe(Position.self) { _ in firstChanges += 1 }
    let second = world.observe(Position.self) { _ in secondChanges += 1 }
    let health = world.observe(Health.self) { _ in healthChanges += 1 }
    world.removeObserver(first)
    entity.set(Position(x: 1, y: 2))
    #expect(firstChanges == 0)
    #expect(secondChanges == 1)
    world.removeObserver(second)
    world.removeObserver(second)
    entity.set(Position(x: 3, y: 4))
    entity.set(Health(current: 5))
    #expect(secondChanges == 1)
    #expect(healthChanges == 1)
    world.removeObserver(health)
    entity.set(Position(x: 0, y: 0))
    entity.remove(Position.self)
    #expect(secondChanges == 1)
    let replacement = world.observe(Position.self) { _ in secondChanges += 1 }
    world.removeObserver(second)
    entity.set(Position(x: 0, y: 0))
    #expect(secondChanges == 2)
    world.removeObserver(replacement)
}

@Test func `observers can remove themselves during dispatch`() {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0))
    var token: ObservationToken?
    var changes = 0
    token = world.observe(Position.self) { _ in
        changes += 1
        if let token {
            world.removeObserver(token)
        }
    }
    entity.set(Position(x: 1, y: 2))
    entity.set(Position(x: 3, y: 4))
    #expect(changes == 1)
}

private enum FirstNamespace {
    struct SharedName: Component {}
}

private enum SecondNamespace {
    struct SharedName: Component {}
}

@Test func `observer dispatch distinguishes component identity from debug names`() {
    let world = World()
    let entity = world.createEntity()
    var firstEvents = 0
    var secondEvents = 0
    let first = world.observe(FirstNamespace.SharedName.self) { _ in firstEvents += 1 }
    let second = world.observe(SecondNamespace.SharedName.self) { _ in secondEvents += 1 }
    entity.set(FirstNamespace.SharedName())
    entity.set(FirstNamespace.SharedName())
    entity.remove(FirstNamespace.SharedName.self)
    #expect(firstEvents == 3)
    #expect(secondEvents == 0)
    entity.set(SecondNamespace.SharedName())
    #expect(secondEvents == 1)
    world.removeObserver(first)
    entity.set(FirstNamespace.SharedName())
    entity.set(SecondNamespace.SharedName())
    #expect(firstEvents == 3)
    #expect(secondEvents == 2)
    world.removeObserver(second)
}
