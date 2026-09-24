import Observation
import SwiftECS
import Testing

// The test and observation callback execute synchronously on one thread.
private final class ComponentRefChange: @unchecked Sendable {
    var notifications = 0
    let read: () -> Void

    init(read: @escaping () -> Void) {
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

@Test func `component references mutate only the selected type`() throws {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
    let row = try #require(world.query(Position.self, Velocity.self).first { _ in true })
    let (position, velocity) = row.components
    var positionEvents = 0
    var velocityEvents = 0
    let positionToken = world.observe(Position.self) { _ in positionEvents += 1 }
    let velocityToken = world.observe(Velocity.self) { _ in velocityEvents += 1 }
    let change = ComponentRefChange { _ = position.value }
    position.value.x += velocity.value.dx
    #expect(position.entityID == entity.id)
    #expect(entity[Position.self]?.x == 4)
    #expect(entity[Velocity.self]?.dx == 3)
    #expect(positionEvents == 1)
    #expect(velocityEvents == 0)
    #expect(change.notifications == 1)
    world.removeObserver(positionToken)
    world.removeObserver(velocityToken)
}

private struct SelectiveMovementSystem: System {
    func update(world: World, deltaTime: Double) {
        for row in world.query(Position.self, Velocity.self) {
            let (position, velocity) = row.components
            position.value.x += velocity.value.dx * deltaTime
        }
    }
}

@Test func `selective writes inside a system preserve batched invalidation`() throws {
    let world = World()
    for _ in 0..<10 {
        world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    }
    var positionEvents = 0
    var velocityEvents = 0
    let positionToken = world.observe(Position.self) { _ in positionEvents += 1 }
    let velocityToken = world.observe(Velocity.self) { _ in velocityEvents += 1 }
    try world.addSystem(SelectiveMovementSystem())
    let change = ComponentRefChange { _ = world.entityCount }
    try world.update(deltaTime: 1)
    #expect(positionEvents == 10)
    #expect(velocityEvents == 0)
    #expect(change.notifications == 1)
    #expect(world.query(Position.self).allSatisfy { $0.values.x == 1 })
    world.removeObserver(positionToken)
    world.removeObserver(velocityToken)
}

@Test func `single component references support full replacement`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 10))
    let row = try #require(world.query(Health.self).first { _ in true })
    let health = row.components
    health.value = Health(current: 20)
    #expect(entity[Health.self]?.current == 20)
    #expect(row.values.current == 20)
}
