@testable import ECS
import Testing

@Test func `observer removal preserves other subscribers and allows registration again`() {
    let world = World()
    let entity = world.createEntity()
    let registry = ObserverRegistry()
    var firstChanges = 0
    var secondChanges = 0
    var healthChanges = 0
    let first = registry.observe(Position.self) { _ in firstChanges += 1 }
    let second = registry.observe(Position.self) { _ in secondChanges += 1 }
    let health = registry.observe(Health.self) { _ in healthChanges += 1 }
    registry.removeObserver(first)
    #expect(registry.hasObservers(for: Position.self))
    registry.notifyChanged(entity: entity, component: Position(x: 1, y: 2))
    #expect(firstChanges == 0)
    #expect(secondChanges == 1)
    registry.removeObserver(second)
    registry.removeObserver(second)
    #expect(!registry.hasObservers(for: Position.self))
    #expect(registry.hasObservers(for: Health.self))
    registry.notifyChanged(entity: entity, component: Position(x: 3, y: 4))
    registry.notifyChanged(entity: entity, component: Health(current: 5))
    #expect(secondChanges == 1)
    #expect(healthChanges == 1)
    registry.removeObserver(health)
    #expect(!registry.hasObservers(for: Health.self))
    registry.notifyAdded(entity: entity, component: Position(x: 0, y: 0))
    registry.notifyChanged(entity: entity, component: Position(x: 0, y: 0))
    registry.notifyRemoved(entity: entity, component: Position(x: 0, y: 0))
    let replacement = registry.observe(Position.self) { _ in secondChanges += 1 }
    registry.removeObserver(second)
    registry.notifyAdded(entity: entity, component: Position(x: 0, y: 0))
    #expect(secondChanges == 2)
    registry.removeObserver(replacement)
}

@Test func `observers can remove themselves during dispatch`() {
    let world = World()
    let registry = ObserverRegistry()
    let entity = world.createEntity()
    var token: ObservationToken?
    var changes = 0
    token = registry.observe(Position.self) { _ in
        changes += 1
        if let token {
            registry.removeObserver(token)
        }
    }
    registry.notifyChanged(entity: entity, component: Position(x: 1, y: 2))
    registry.notifyChanged(entity: entity, component: Position(x: 3, y: 4))
    #expect(changes == 1)
    #expect(!registry.hasObservers(for: Position.self))
}

private enum FirstNamespace {
    struct SharedName: Component {}
}

private enum SecondNamespace {
    struct SharedName: Component {}
}

@Test func `observer dispatch distinguishes component identity from debug names`() {
    let registry = ObserverRegistry()
    let entity = World().createEntity()
    var firstEvents = 0
    var secondEvents = 0
    let first = registry.observe(FirstNamespace.SharedName.self) { _ in firstEvents += 1 }
    let second = registry.observe(SecondNamespace.SharedName.self) { _ in secondEvents += 1 }
    registry.notifyAdded(entity: entity, component: FirstNamespace.SharedName())
    registry.notifyChanged(entity: entity, component: FirstNamespace.SharedName())
    registry.notifyRemoved(entity: entity, component: FirstNamespace.SharedName())
    #expect(firstEvents == 3)
    #expect(secondEvents == 0)
    registry.notifyChanged(entity: entity, component: SecondNamespace.SharedName())
    #expect(secondEvents == 1)
    registry.removeObserver(first)
    #expect(registry.hasObservers(for: SecondNamespace.SharedName.self))
    registry.removeObserver(second)
}
