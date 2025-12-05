@testable import ECS
import Testing

// MARK: - Entity Tests

@Test func testCreateEntity() {
    let world = World()
    let entity = world.createEntity()

    #expect(world.entityCount == 1)
    #expect(entity.exists)
}

@Test func testCreateEntityWithComponent() {
    let world = World()
    let entity = world.createEntity( Position(x: 10, y: 20))

    #expect(world.entityCount == 1)
    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Position.self]?.y == 20)
}

@Test func testCreateEntityWithTwoComponents() {
    let world = World()
    let entity = world.createEntity(
        Position(x: 10, y: 20),
        Velocity(dx: 1, dy: 2)
    )

    #expect(world.entityCount == 1)
    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Velocity.self]?.dx == 1)
}

@Test func testCreateEntityWithThreeComponents() {
    let world = World()
    let entity = world.createEntity(
        Position(x: 10, y: 20),
        Velocity(dx: 1, dy: 2),
        Health(current: 100)
    )

    #expect(world.entityCount == 1)
    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Velocity.self]?.dx == 1)
    #expect(entity[Health.self]?.current == 100)
}

@Test func testRemoveEntity() {
    let world = World()
    let e1 = world.createEntity( Position(x: 1, y: 1))
    let e2 = world.createEntity( Position(x: 2, y: 2))
    let e3 = world.createEntity( Position(x: 3, y: 3))

    #expect(world.entityCount == 3)

    let removed = e2.destroy()
    #expect(removed == true)
    #expect(world.entityCount == 2)
    #expect(e2.exists == false)

    // Other entities still exist
    #expect(e1.exists)
    #expect(e3.exists)
    #expect(e1[Position.self]?.x == 1)
    #expect(e3[Position.self]?.x == 3)
}

@Test func testRemoveNonexistentEntity() {
    let world = World()
    let fakeID = EntityID(999)

    // Use subscript to try to get entity
    let entity = world[fakeID]
    #expect(entity == nil)
}

@Test func testAllEntities() {
    let world = World()

    #expect(world.entities.isEmpty)

    let e1 = world.createEntity()
    let e2 = world.createEntity()

    let all = world.entities
    #expect(all.count == 2)
    #expect(all.contains { $0.id == e1.id })
    #expect(all.contains { $0.id == e2.id })
}

// MARK: - Component Tests

@Test func testAddComponent() {
    let world = World()
    let entity = world.createEntity()

    entity.add(Position(x: 10, y: 20))

    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Position.self]?.y == 20)
}

@Test func testAddMultipleComponents() {
    let world = World()
    let entity = world.createEntity()

    entity.add(Position(x: 1, y: 2))
    entity.add(Velocity(dx: 3, dy: 4))

    #expect(entity[Position.self]?.x == 1)
    #expect(entity[Velocity.self]?.dx == 3)
}

@Test func testAddComponentChaining() {
    let world = World()
    let entity = world.createEntity()
        .add(Position(x: 1, y: 2))
        .add(Velocity(dx: 3, dy: 4))

    #expect(entity[Position.self]?.x == 1)
    #expect(entity[Velocity.self]?.dx == 3)
}

@Test func testUpdateComponent() {
    let world = World()
    let entity = world.createEntity( Position(x: 1, y: 2))

    entity.add(Position(x: 100, y: 200))

    #expect(entity[Position.self]?.x == 100)
    #expect(entity[Position.self]?.y == 200)
}

@Test func testRemoveComponent() {
    let world = World()
    let entity = world.createEntity(
        Position(x: 10, y: 20),
        Velocity(dx: 1, dy: 2)
    )

    let removed = entity.remove(Position.self)
    #expect(removed?.x == 10)
    #expect(entity[Position.self] == nil)
    #expect(entity[Velocity.self]?.dx == 1)
}

@Test func testRemoveNonexistentComponent() {
    let world = World()
    let entity = world.createEntity( Position(x: 1, y: 2))

    let removed = entity.remove(Velocity.self)
    #expect(removed == nil)
}

@Test func testHasComponent() {
    let world = World()
    let entity = world.createEntity( Position(x: 1, y: 2))

    #expect(entity.has(Position.self) == true)
    #expect(entity.has(Velocity.self) == false)
}

@Test func testAddComponentToNonexistentEntity() {
    let world = World()
    let entity = world.createEntity()
    entity.destroy()

    // Should not crash - entity no longer exists
    entity.add(Position(x: 0, y: 0))
    #expect(entity[Position.self] == nil)
}

// MARK: - Iteration Tests

@Test func testForEachSingleComponent() {
    let world = World()

    world.createEntity( Position(x: 1, y: 1))
    world.createEntity( Position(x: 2, y: 2))
    world.createEntity( Position(x: 3, y: 3))

    var sum = 0.0
    world.forEach(Position.self) { _, pos in
        sum += pos.x + pos.y
    }

    #expect(sum == 12.0)  // (1+1) + (2+2) + (3+3)
}

@Test func testForEachMutableSingleComponent() {
    let world = World()

    let e1 = world.createEntity( Position(x: 1, y: 1))
    let e2 = world.createEntity( Position(x: 2, y: 2))

    world.forEachMutable(Position.self) { _, pos in
        pos.x *= 10
        pos.y *= 10
    }

    #expect(e1[Position.self]?.x == 10)
    #expect(e2[Position.self]?.x == 20)
}

@Test func testForEachTwoComponents() {
    let world = World()

    world.createEntity( Position(x: 0, y: 0), Velocity(dx: 1, dy: 1))
    world.createEntity( Position(x: 10, y: 10), Velocity(dx: 2, dy: 2))
    world.createEntity( Position(x: 100, y: 100))  // No velocity

    var count = 0
    world.forEach(Position.self, Velocity.self) { _, pos, vel in
        count += 1
        #expect(pos.x >= 0)
        #expect(vel.dx > 0)
    }

    #expect(count == 2)
}

@Test func testForEachMutableTwoComponents() {
    let world = World()

    let entity = world.createEntity(
        Position(x: 0, y: 0),
        Velocity(dx: 10, dy: 5)
    )

    world.forEachMutable(Position.self, Velocity.self) { _, pos, vel in
        pos.x += vel.dx
        pos.y += vel.dy
    }

    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Position.self]?.y == 5)
}

@Test func testForEachMutableThreeComponents() {
    let world = World()

    let entity = world.createEntity(
        Position(x: 100, y: 100),
        Velocity(dx: 10, dy: 10),
        Health(current: 100)
    )

    world.forEachMutable(Position.self, Velocity.self, Health.self) { _, pos, vel, health in
        pos.x += vel.dx
        health.current -= 10
    }

    #expect(entity[Position.self]?.x == 110)
    #expect(entity[Health.self]?.current == 90)
}

// MARK: - Query Tests

@Test func testEntitiesWithComponent() {
    let world = World()

    let e1 = world.createEntity( Position(x: 1, y: 1))
    let e2 = world.createEntity( Position(x: 2, y: 2), Velocity(dx: 1, dy: 1))
    let e3 = world.createEntity( Velocity(dx: 2, dy: 2))

    let withPos = world.entities(with: Position.self)
    #expect(withPos.count == 2)
    #expect(withPos.contains { $0.id == e1.id })
    #expect(withPos.contains { $0.id == e2.id })
    #expect(!withPos.contains { $0.id == e3.id })

    let withVel = world.entities(with: Velocity.self)
    #expect(withVel.count == 2)
    #expect(withVel.contains { $0.id == e2.id })
    #expect(withVel.contains { $0.id == e3.id })
}

@Test func testEntitiesWithAllComponents() {
    let world = World()

    world.createEntity( Position(x: 1, y: 1))
    let e2 = world.createEntity( Position(x: 2, y: 2), Velocity(dx: 1, dy: 1))
    world.createEntity( Velocity(dx: 2, dy: 2))

    let withBoth = world.entities(with: Position.self, Velocity.self)
    #expect(withBoth.count == 1)
    #expect(withBoth.first?.id == e2.id)
}

@Test func testEntitiesEmpty() {
    let world = World()

    world.createEntity()
    world.createEntity()
    world.createEntity()

    let all = world.entities
    #expect(all.count == 3)
}

// MARK: - System Tests

@Test func testSystemUpdate() {
    let world = World()
    let entity = world.createEntity(
        Position(x: 0, y: 0),
        Velocity(dx: 10, dy: 5)
    )

    world.addSystem(MovementSystem())
    world.update(deltaTime: 1.0)

    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Position.self]?.y == 5)
}

@Test func testMultipleEntitiesWithSystem() {
    let world = World()

    let entity1 = world.createEntity(
        Position(x: 0, y: 0),
        Velocity(dx: 10, dy: 5)
    )
    let entity2 = world.createEntity(
        Position(x: 100, y: 100),
        Velocity(dx: -5, dy: -10)
    )

    world.addSystem(MovementSystem())
    world.update(deltaTime: 2.0)

    #expect(entity1[Position.self]?.x == 20)
    #expect(entity1[Position.self]?.y == 10)

    #expect(entity2[Position.self]?.x == 90)
    #expect(entity2[Position.self]?.y == 80)
}

@Test func testInitializableSystem() {
    let world = World()
    world.addSystem(InitializableMovementSystem())

    // Just verify no crash - system should have been initialized
    #expect(world.entityCount == 0)
}

@Test func testCleanupSystem() {
    let world = World()
    world.addSystem(CleanupMovementSystem())
    world.removeAllSystems()

    // Verify systems were removed
    world.update(deltaTime: 1.0)  // Should do nothing
}

// MARK: - Entity Handle Tests

@Test func testEntitySubscript() {
    let world = World()
    let entity = world.createEntity( Position(x: 10, y: 20))

    let fetched = world[entity.id]
    #expect(fetched != nil)
    #expect(fetched?.id == entity.id)
    #expect(fetched?.exists == true)
    #expect(fetched?[Position.self]?.x == 10)
    #expect(fetched?.has(Position.self) == true)
    #expect(fetched?.has(Velocity.self) == false)
}

@Test func testEntitySubscriptNonexistent() {
    let world = World()
    let entity = world[EntityID(999)]
    #expect(entity == nil)
}

@Test func testEntityExistsAfterDestroy() {
    let world = World()
    let entity = world.createEntity( Position(x: 1, y: 2))

    #expect(entity.exists == true)

    entity.destroy()
    #expect(entity.exists == false)
}
