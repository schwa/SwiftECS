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
    let entity = world.createEntity(Position(x: 10, y: 20))

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
    let e1 = world.createEntity(Position(x: 1, y: 1))
    let e2 = world.createEntity(Position(x: 2, y: 2))
    let e3 = world.createEntity(Position(x: 3, y: 3))

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
    let fakeID = EntityID()

    // Use subscript to try to get entity
    let entity = world[fakeID]
    #expect(entity == nil)
}

@Test func testCloneEntity() {
    let world = World()
    let original = world.createEntity(
        Position(x: 10, y: 20),
        Velocity(dx: 1, dy: 2)
    )

    let cloned = original.clone()

    #expect(cloned != nil)
    #expect(cloned?.id != original.id)
    #expect(cloned?[Position.self]?.x == 10)
    #expect(cloned?[Position.self]?.y == 20)
    #expect(cloned?[Velocity.self]?.dx == 1)
    #expect(cloned?[Velocity.self]?.dy == 2)
    #expect(world.entityCount == 2)
}

@Test func testCloneEntityIndependence() {
    let world = World()
    let original = world.createEntity(Position(x: 10, y: 20))

    let cloned = original.clone()!

    // Modify original
    original.set(Position(x: 100, y: 200))

    // Clone should be unaffected
    #expect(original[Position.self]?.x == 100)
    #expect(cloned[Position.self]?.x == 10)
}

@Test func testCloneEmptyEntity() {
    let world = World()
    let original = world.createEntity()

    let cloned = original.clone()

    #expect(cloned != nil)
    #expect(cloned?.id != original.id)
    #expect(world.entityCount == 2)
}

@Test func testCloneNonexistentEntity() {
    let world = World()
    let entity = world.createEntity()
    entity.destroy()

    let cloned = entity.clone()

    #expect(cloned == nil)
}

@Test func testAllEntities() {
    let world = World()

    #expect(world.query(.all).isEmpty)

    let e1 = world.createEntity()
    let e2 = world.createEntity()

    let all = world.query(.all)
    #expect(all.count == 2)
    #expect(all.contains { $0.id == e1.id })
    #expect(all.contains { $0.id == e2.id })
}

// MARK: - Component Tests

@Test func testSetComponent() {
    let world = World()
    let entity = world.createEntity()

    entity.set(Position(x: 10, y: 20))

    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Position.self]?.y == 20)
}

@Test func testSetMultipleComponents() {
    let world = World()
    let entity = world.createEntity()

    entity.set(Position(x: 1, y: 2))
    entity.set(Velocity(dx: 3, dy: 4))

    #expect(entity[Position.self]?.x == 1)
    #expect(entity[Velocity.self]?.dx == 3)
}

@Test func testSetComponentChaining() {
    let world = World()
    let entity = world.createEntity()
        .set(Position(x: 1, y: 2))
        .set(Velocity(dx: 3, dy: 4))

    #expect(entity[Position.self]?.x == 1)
    #expect(entity[Velocity.self]?.dx == 3)
}

@Test func testUpdateComponent() {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2))

    entity.set(Position(x: 100, y: 200))

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
    let entity = world.createEntity(Position(x: 1, y: 2))

    let removed = entity.remove(Velocity.self)
    #expect(removed == nil)
}

@Test func testContainsComponent() {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2))

    #expect(entity.contains(Position.self) == true)
    #expect(entity.contains(Velocity.self) == false)
}

@Test func testSetComponentToNonexistentEntity() {
    let world = World()
    let entity = world.createEntity()
    entity.destroy()

    // Should not crash - entity no longer exists
    entity.set(Position(x: 0, y: 0))
    #expect(entity[Position.self] == nil)
}

// MARK: - Iteration Tests

@Test func testQueryIterationSingleComponent() {
    let world = World()

    world.createEntity(Position(x: 1, y: 1))
    world.createEntity(Position(x: 2, y: 2))
    world.createEntity(Position(x: 3, y: 3))

    var sum = 0.0
    for entity in world.query(with: Position.self) {
        let pos = entity.get(Position.self)!.values
        sum += pos.x + pos.y
    }

    #expect(sum == 12.0)  // (1+1) + (2+2) + (3+3)
}

@Test func testQueryIterationMutableSingleComponent() {
    let world = World()

    let e1 = world.createEntity(Position(x: 1, y: 1))
    let e2 = world.createEntity(Position(x: 2, y: 2))

    for entity in world.query(with: Position.self) {
        var pos = entity[Position.self]!
        pos.x *= 10
        pos.y *= 10
        entity.set(pos)
    }

    #expect(e1[Position.self]?.x == 10)
    #expect(e2[Position.self]?.x == 20)
}

@Test func testQueryIterationTwoComponents() {
    let world = World()

    world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1))
    world.createEntity(Position(x: 10, y: 10), Velocity(dx: 2, dy: 2))
    world.createEntity(Position(x: 100, y: 100))  // No velocity

    var count = 0
    for entity in world.query(with: Position.self, Velocity.self) {
        let (pos, vel) = entity.get(Position.self, Velocity.self)!.values
        count += 1
        #expect(pos.x >= 0)
        #expect(vel.dx > 0)
    }

    #expect(count == 2)
}

@Test func testQueryIterationMutableTwoComponents() {
    let world = World()

    let entity = world.createEntity(
        Position(x: 0, y: 0),
        Velocity(dx: 10, dy: 5)
    )

    for e in world.query(with: Position.self, Velocity.self) {
        var (pos, vel) = e.get(Position.self, Velocity.self)!.values
        pos.x += vel.dx
        pos.y += vel.dy
        e.set(pos, vel)
    }

    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Position.self]?.y == 5)
}

@Test func testQueryIterationMutableThreeComponents() {
    let world = World()

    let entity = world.createEntity(
        Position(x: 100, y: 100),
        Velocity(dx: 10, dy: 10),
        Health(current: 100)
    )

    for e in world.query(with: Position.self, Velocity.self, Health.self) {
        var (pos, vel, health) = e.get(Position.self, Velocity.self, Health.self)!.values
        pos.x += vel.dx
        health.current -= 10
        e.set(pos, vel, health)
    }

    #expect(entity[Position.self]?.x == 110)
    #expect(entity[Health.self]?.current == 90)
}

// MARK: - Query Tests

@Test func testQueryWithComponent() {
    let world = World()

    let e1 = world.createEntity(Position(x: 1, y: 1))
    let e2 = world.createEntity(Position(x: 2, y: 2), Velocity(dx: 1, dy: 1))
    let e3 = world.createEntity(Velocity(dx: 2, dy: 2))

    let withPos = world.query(with: Position.self)
    #expect(withPos.count == 2)
    #expect(withPos.contains { $0.id == e1.id })
    #expect(withPos.contains { $0.id == e2.id })
    #expect(!withPos.contains { $0.id == e3.id })

    let withVel = world.query(with: Velocity.self)
    #expect(withVel.count == 2)
    #expect(withVel.contains { $0.id == e2.id })
    #expect(withVel.contains { $0.id == e3.id })
}

@Test func testQueryWithAllComponents() {
    let world = World()

    world.createEntity(Position(x: 1, y: 1))
    let e2 = world.createEntity(Position(x: 2, y: 2), Velocity(dx: 1, dy: 1))
    world.createEntity(Velocity(dx: 2, dy: 2))

    let withBoth = world.query(with: Position.self, Velocity.self)
    #expect(withBoth.count == 1)
    #expect(withBoth.first?.id == e2.id)
}

@Test func testQueryAll() {
    let world = World()

    world.createEntity()
    world.createEntity()
    world.createEntity()

    let all = world.query(.all)
    #expect(all.count == 3)
}

// MARK: - System Tests

@Test func testSystemUpdate() throws {
    let world = World()
    let entity = world.createEntity(
        Position(x: 0, y: 0),
        Velocity(dx: 10, dy: 5)
    )

    world.addSystem(MovementSystem())
    try world.update(deltaTime: 1.0)

    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Position.self]?.y == 5)
}

@Test func testMultipleEntitiesWithSystem() throws {
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
    try world.update(deltaTime: 2.0)

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

@Test func testCleanupSystem() throws {
    let world = World()
    world.addSystem(CleanupMovementSystem())
    world.removeAllSystems()

    // Verify systems were removed
    try world.update(deltaTime: 1.0)  // Should do nothing
}

// MARK: - Entity Handle Tests

@Test func testEntitySubscript() {
    let world = World()
    let entity = world.createEntity(Position(x: 10, y: 20))

    let fetched = world[entity.id]
    #expect(fetched != nil)
    #expect(fetched?.id == entity.id)
    #expect(fetched?.exists == true)
    #expect(fetched?[Position.self]?.x == 10)
    #expect(fetched?.contains(Position.self) == true)
    #expect(fetched?.contains(Velocity.self) == false)
}

@Test func testEntitySubscriptNonexistent() {
    let world = World()
    let entity = world[EntityID()]
    #expect(entity == nil)
}

@Test func testComponentSubscriptSet() {
    let world = World()
    let entity = world.createEntity()

    entity[Position.self] = Position(x: 10, y: 20)

    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Position.self]?.y == 20)
}

@Test func testComponentSubscriptUpdate() {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2))

    entity[Position.self] = Position(x: 100, y: 200)

    #expect(entity[Position.self]?.x == 100)
    #expect(entity[Position.self]?.y == 200)
}

@Test func testComponentSubscriptRemoveWithNil() {
    let world = World()
    let entity = world.createEntity(Position(x: 10, y: 20), Velocity(dx: 1, dy: 2))

    #expect(entity.contains(Position.self) == true)

    entity[Position.self] = nil

    #expect(entity.contains(Position.self) == false)
    #expect(entity[Position.self] == nil)
    // Other components unaffected
    #expect(entity[Velocity.self]?.dx == 1)
}

@Test func testComponentSubscriptRemoveNonexistent() {
    let world = World()
    let entity = world.createEntity(Position(x: 10, y: 20))

    // Should not crash when removing component that doesn't exist
    entity[Velocity.self] = nil

    #expect(entity.contains(Position.self) == true)
    #expect(entity.contains(Velocity.self) == false)
}

@Test func testEntityExistsAfterDestroy() {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2))

    #expect(entity.exists == true)

    entity.destroy()
    #expect(entity.exists == false)
}

// MARK: - Composite Get Tests

@Test func testEntityGetSingleComponent() {
    let world = World()
    let entity = world.createEntity(Position(x: 10, y: 20))

    let composite = entity.get(Position.self)
    #expect(composite != nil)

    if let composite {
        let (pos) = composite.values
        #expect(pos.x == 10)
        #expect(pos.y == 20)
    }
}

@Test func testEntityGetMultipleComponents() {
    let world = World()
    let entity = world.createEntity(
        Position(x: 10, y: 20),
        Velocity(dx: 1, dy: 2),
        Health(current: 100)
    )

    let composite = entity.get(Position.self, Velocity.self, Health.self)
    #expect(composite != nil)

    if let composite {
        let (pos, vel, health) = composite.values
        #expect(pos.x == 10)
        #expect(pos.y == 20)
        #expect(vel.dx == 1)
        #expect(vel.dy == 2)
        #expect(health.current == 100)
    }
}

@Test func testEntityGetMissingComponent() {
    let world = World()
    let entity = world.createEntity(Position(x: 10, y: 20))

    // Request a component that doesn't exist
    let composite = entity.get(Position.self, Velocity.self)
    #expect(composite == nil)
}

@Test func testEntityGetPartialComponents() {
    let world = World()
    let entity = world.createEntity(
        Position(x: 10, y: 20),
        Health(current: 50)
    )

    // Request Position and Velocity, but entity only has Position and Health
    let composite = entity.get(Position.self, Velocity.self)
    #expect(composite == nil)

    // Request Position and Health - should work
    let validComposite = entity.get(Position.self, Health.self)
    #expect(validComposite != nil)

    if let validComposite {
        let (pos, health) = validComposite.values
        #expect(pos.x == 10)
        #expect(health.current == 50)
    }
}

@Test func testEntitySetMultipleComponents() {
    let world = World()
    let entity = world.createEntity()

    entity.set(Position(x: 10, y: 20), Velocity(dx: 1, dy: 2), Health(current: 100))

    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Velocity.self]?.dx == 1)
    #expect(entity[Health.self]?.current == 100)
}

@Test func testEntitySetFromComposite() {
    let world = World()
    let entity1 = world.createEntity(
        Position(x: 10, y: 20),
        Velocity(dx: 1, dy: 2)
    )

    let entity2 = world.createEntity()

    // Get components from entity1 and set on entity2
    if let composite = entity1.get(Position.self, Velocity.self) {
        entity2.set(composite)
    }

    #expect(entity2[Position.self]?.x == 10)
    #expect(entity2[Position.self]?.y == 20)
    #expect(entity2[Velocity.self]?.dx == 1)
    #expect(entity2[Velocity.self]?.dy == 2)
}

@Test func testEntitySetChaining() {
    let world = World()
    let entity = world.createEntity()
        .set(Position(x: 5, y: 10))
        .set(Velocity(dx: 1, dy: 2), Health(current: 50))

    #expect(entity[Position.self]?.x == 5)
    #expect(entity[Velocity.self]?.dx == 1)
    #expect(entity[Health.self]?.current == 50)
}

@Test func testEntitySetUpdatesExisting() {
    let world = World()
    let entity = world.createEntity(
        Position(x: 10, y: 20),
        Velocity(dx: 1, dy: 2)
    )

    entity.set(Position(x: 100, y: 200), Velocity(dx: 10, dy: 20))

    #expect(entity[Position.self]?.x == 100)
    #expect(entity[Position.self]?.y == 200)
    #expect(entity[Velocity.self]?.dx == 10)
    #expect(entity[Velocity.self]?.dy == 20)
}

// MARK: - Observer Tests

@Test func testObserveComponentAdded() {
    let world = World()
    var addedPositions: [(EntityID, Position)] = []

    let token = world.observe(Position.self) { event in
        if case let .added(entity, position) = event {
            addedPositions.append((entity.id, position))
        }
    }

    let entity = world.createEntity()
    entity.set(Position(x: 10, y: 20))

    #expect(addedPositions.count == 1)
    #expect(addedPositions[0].0 == entity.id)
    #expect(addedPositions[0].1.x == 10)
    #expect(addedPositions[0].1.y == 20)

    world.removeObserver(token)
}

@Test func testObserveComponentRemoved() {
    let world = World()
    var removedPositions: [(EntityID, Position)] = []

    let token = world.observe(Position.self) { event in
        if case let .removed(entity, position) = event {
            removedPositions.append((entity.id, position))
        }
    }

    let entity = world.createEntity(Position(x: 10, y: 20))
    entity.remove(Position.self)

    #expect(removedPositions.count == 1)
    #expect(removedPositions[0].0 == entity.id)
    #expect(removedPositions[0].1.x == 10)

    world.removeObserver(token)
}

@Test func testObserveComponentRemovedViaSubscriptNil() {
    let world = World()
    var removedCount = 0

    let token = world.observe(Position.self) { event in
        if case .removed = event {
            removedCount += 1
        }
    }

    let entity = world.createEntity(Position(x: 10, y: 20))
    entity[Position.self] = nil

    #expect(removedCount == 1)

    world.removeObserver(token)
}

@Test func testObserverNotCalledAfterRemoval() {
    let world = World()
    var addedCount = 0

    let token = world.observe(Position.self) { event in
        if case .added = event {
            addedCount += 1
        }
    }

    let entity1 = world.createEntity()
    entity1.set(Position(x: 1, y: 1))
    #expect(addedCount == 1)

    world.removeObserver(token)

    let entity2 = world.createEntity()
    entity2.set(Position(x: 2, y: 2))
    #expect(addedCount == 1)  // Should not have incremented
}

@Test func testMultipleObserversForSameType() {
    let world = World()
    var observer1Count = 0
    var observer2Count = 0

    let token1 = world.observe(Position.self) { _ in observer1Count += 1 }
    let token2 = world.observe(Position.self) { _ in observer2Count += 1 }

    let entity = world.createEntity()
    entity.set(Position(x: 10, y: 20))

    #expect(observer1Count == 1)
    #expect(observer2Count == 1)

    world.removeObserver(token1)
    world.removeObserver(token2)
}

@Test func testObserverForDifferentTypes() {
    let world = World()
    var positionEvents = 0
    var velocityEvents = 0

    let token1 = world.observe(Position.self) { _ in positionEvents += 1 }
    let token2 = world.observe(Velocity.self) { _ in velocityEvents += 1 }

    let entity = world.createEntity()
    entity.set(Position(x: 10, y: 20))
    entity.set(Velocity(dx: 1, dy: 2))

    #expect(positionEvents == 1)
    #expect(velocityEvents == 1)

    entity.remove(Position.self)

    #expect(positionEvents == 2)  // added + removed
    #expect(velocityEvents == 1)

    world.removeObserver(token1)
    world.removeObserver(token2)
}

@Test func testObserverChangeEvent() {
    let world = World()
    var addedCount = 0
    var changedCount = 0

    let token = world.observe(Position.self) { event in
        switch event {
        case .added: addedCount += 1
        case .changed: changedCount += 1
        case .removed: break
        }
    }

    let entity = world.createEntity()
    entity.set(Position(x: 10, y: 20))
    #expect(addedCount == 1)
    #expect(changedCount == 0)

    // Update existing component - should trigger change event
    entity.set(Position(x: 100, y: 200))
    #expect(addedCount == 1)
    #expect(changedCount == 1)

    // Another update
    entity.set(Position(x: 500, y: 600))
    #expect(addedCount == 1)
    #expect(changedCount == 2)

    world.removeObserver(token)
}

// MARK: - Debug Tests

@Test func testWorldStats() {
    let world = World()

    world.createEntity(Position(x: 0, y: 0))
    world.createEntity(Position(x: 1, y: 1), Velocity(dx: 1, dy: 1))
    world.createEntity(Velocity(dx: 2, dy: 2))

    world.addSystem(MovementSystem())

    let stats = world.stats

    #expect(stats.entityCount == 3)
    #expect(stats.archetypeCount == 4)  // empty + Position + Position,Velocity + Velocity
    #expect(stats.componentTypeCount == 2)  // Position, Velocity
    #expect(stats.systemCount == 1)
}

@Test func testComponentTypesForEntity() {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1))

    let types = world.componentTypes(for: entity)

    #expect(types.count == 2)
    let typeNames = types.map(\.name).sorted()
    #expect(typeNames == ["Position", "Velocity"])
}

@Test func testComponentTypesForEmptyEntity() {
    let world = World()
    let entity = world.createEntity()

    let types = world.componentTypes(for: entity)

    #expect(types.isEmpty)
}

@Test func testEntityComponentTypesProperty() {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1))

    let types = entity.componentTypes

    #expect(types.count == 2)
    let typeNames = types.map(\.name).sorted()
    #expect(typeNames == ["Position", "Velocity"])
}

@Test func testEntityComponentTypesPropertyEmpty() {
    let world = World()
    let entity = world.createEntity()

    #expect(entity.componentTypes.isEmpty)
}

@Test func testEntityComponentTypesUpdatesAfterChange() {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0))

    #expect(entity.componentTypes.count == 1)

    entity.set(Velocity(dx: 1, dy: 1))
    #expect(entity.componentTypes.count == 2)

    entity.remove(Position.self)
    #expect(entity.componentTypes.count == 1)
    #expect(entity.componentTypes.first?.name == "Velocity")
}

@Test func testComponentTypePrintsTypeName() {
    let componentType = ComponentType(Position.self)

    #expect(String(describing: componentType) == "Position")
    #expect(componentType.description == "Position")
    #expect("\(componentType)" == "Position")
}

@Test func testEntityIsIdentifiable() {
    let world = World()
    let entity = world.createEntity()

    // Entity conforms to Identifiable
    let id: EntityID = entity.id
    #expect(id == entity.id)

    // Can be used in contexts requiring Identifiable
    let entities = [
        world.createEntity(Position(x: 0, y: 0)),
        world.createEntity(Position(x: 1, y: 1)),
        world.createEntity(Position(x: 2, y: 2))
    ]

    // Identifiable allows use with SwiftUI ForEach, etc.
    let ids = entities.map(\.id)
    #expect(ids.count == 3)
    #expect(Set(ids).count == 3)  // All unique
}

// MARK: - SystemID Tests

@Test func testSystemIDFromString() {
    let id = SystemID("physics")
    #expect(id.value == "physics")
}

@Test func testSystemIDStringLiteral() {
    let id: SystemID = "physics"
    #expect(id.value == "physics")
}

@Test func testSystemIDEquality() {
    let id1: SystemID = "physics"
    let id2: SystemID = "physics"
    let id3: SystemID = "render"

    #expect(id1 == id2)
    #expect(id1 != id3)
}

@Test func testSystemIDHashable() {
    let id1: SystemID = "physics"
    let id2: SystemID = "render"

    var set = Set<SystemID>()
    set.insert(id1)
    set.insert(id2)
    set.insert(id1)  // Duplicate

    #expect(set.count == 2)
}

@Test func testSystemIDDescription() {
    let id: SystemID = "physics"
    #expect(String(describing: id) == "physics")
    #expect("\(id)" == "physics")
}

@Test func testSystemIDFromType() {
    let id = SystemID.of(MovementSystem.self)
    #expect(id.value == "MovementSystem")
}

// MARK: - System Dependency Tests

struct OrderTrackingSystem: System {
    let name: String
    let order: SharedOrder

    func update(world: World, deltaTime: Double) {
        order.append(name)
    }
}

final class SharedOrder: @unchecked Sendable {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func reset() { values.removeAll() }
}

@Test func testSystemExecutionOrder() throws {
    let world = World()
    let order = SharedOrder()

    try world.addSystem(OrderTrackingSystem(name: "A", order: order), id: "A")
    try world.addSystem(OrderTrackingSystem(name: "B", order: order), id: "B")
    try world.addSystem(OrderTrackingSystem(name: "C", order: order), id: "C")

    try world.update(deltaTime: 1.0)

    // Without dependencies, order is registration order
    #expect(order.values == ["A", "B", "C"])
}

@Test func testSystemDependencies() throws {
    let world = World()
    let order = SharedOrder()

    // C depends on B, B depends on A
    try world.addSystem(OrderTrackingSystem(name: "C", order: order), id: "C", dependencies: ["B"])
    try world.addSystem(OrderTrackingSystem(name: "A", order: order), id: "A")
    try world.addSystem(OrderTrackingSystem(name: "B", order: order), id: "B", dependencies: ["A"])

    try world.update(deltaTime: 1.0)

    // Should execute A -> B -> C
    #expect(order.values == ["A", "B", "C"])
}

@Test func testSystemMultipleDependencies() throws {
    let world = World()
    let order = SharedOrder()

    // D depends on both B and C
    try world.addSystem(OrderTrackingSystem(name: "D", order: order), id: "D", dependencies: ["B", "C"])
    try world.addSystem(OrderTrackingSystem(name: "A", order: order), id: "A")
    try world.addSystem(OrderTrackingSystem(name: "B", order: order), id: "B", dependencies: ["A"])
    try world.addSystem(OrderTrackingSystem(name: "C", order: order), id: "C", dependencies: ["A"])

    try world.update(deltaTime: 1.0)

    // A must be first, D must be last, B and C in between
    #expect(order.values.first == "A")
    #expect(order.values.last == "D")
    #expect(order.values.count == 4)
}

@Test func testSystemDuplicateIDError() throws {
    let world = World()
    let order = SharedOrder()

    try world.addSystem(OrderTrackingSystem(name: "A", order: order), id: "physics")

    #expect(throws: SystemError.duplicateID("physics")) {
        try world.addSystem(OrderTrackingSystem(name: "B", order: order), id: "physics")
    }
}

@Test func testSystemDependencyNotFoundError() throws {
    let world = World()
    let order = SharedOrder()

    try world.addSystem(OrderTrackingSystem(name: "A", order: order), id: "A", dependencies: ["nonexistent"])

    #expect(throws: SystemError.dependencyNotFound(system: "A", dependency: "nonexistent")) {
        try world.update(deltaTime: 1.0)
    }
}

@Test func testSystemCyclicDependencyError() throws {
    let world = World()
    let order = SharedOrder()

    try world.addSystem(OrderTrackingSystem(name: "A", order: order), id: "A", dependencies: ["B"])
    try world.addSystem(OrderTrackingSystem(name: "B", order: order), id: "B", dependencies: ["A"])

    #expect {
        try world.update(deltaTime: 1.0)
    } throws: { error in
        guard let systemError = error as? SystemError,
              case .cyclicDependency = systemError else {
            return false
        }
        return true
    }
}

@Test func testSystemExecutionOrderProperty() throws {
    let world = World()
    let order = SharedOrder()

    try world.addSystem(OrderTrackingSystem(name: "C", order: order), id: "C", dependencies: ["B"])
    try world.addSystem(OrderTrackingSystem(name: "A", order: order), id: "A")
    try world.addSystem(OrderTrackingSystem(name: "B", order: order), id: "B", dependencies: ["A"])

    let executionOrder = world.systemExecutionOrder
    #expect(executionOrder == ["A", "B", "C"])
}

@Test func testSystemDefaultID() throws {
    let world = World()

    world.addSystem(MovementSystem())

    let executionOrder = world.systemExecutionOrder
    #expect(executionOrder.contains("MovementSystem"))
}

// MARK: - Query Iterator Tests

@Test func testRegisterQuery() {
    let world = World()
    let query = Query(with: Position.self)
    
    world.register(query)
    
    #expect(world.isRegistered(query))
}

@Test func testEntitiesIterator() {
    let world = World()
    world.createEntity(Position(x: 1, y: 1))
    world.createEntity(Position(x: 2, y: 2))
    world.createEntity(Velocity(dx: 1, dy: 1))
    
    let query = Query(with: Position.self)
    world.register(query)
    
    var sum = 0.0
    for entity in world.entities(query) {
        sum += entity[Position.self]!.x
    }
    
    #expect(sum == 3.0)
}

@Test func testEntitiesIteratorMutation() {
    let world = World()
    let e1 = world.createEntity(Position(x: 1, y: 1))
    let e2 = world.createEntity(Position(x: 2, y: 2))
    
    let query = Query(with: Position.self)
    world.register(query)
    
    for entity in world.entities(query) {
        entity[Position.self]!.x *= 10
    }
    
    #expect(e1[Position.self]?.x == 10)
    #expect(e2[Position.self]?.x == 20)
}

@Test func testEntitiesIteratorTwoComponents() {
    let world = World()
    world.createEntity(Position(x: 1, y: 1), Velocity(dx: 10, dy: 10))
    world.createEntity(Position(x: 2, y: 2), Velocity(dx: 20, dy: 20))
    world.createEntity(Position(x: 3, y: 3))  // No velocity
    
    let query = Query(with: Position.self, Velocity.self)
    world.register(query)
    
    var sum = 0.0
    for entity in world.entities(query) {
        sum += entity[Position.self]!.x + entity[Velocity.self]!.dx
    }
    
    #expect(sum == 33.0)  // (1+10) + (2+20)
}

@Test func testQueryCacheInvalidation() {
    let world = World()
    world.createEntity(Position(x: 1, y: 1))
    
    let query = Query(with: Position.self)
    world.register(query)
    
    // First iteration - builds cache
    var count = 0
    for _ in world.entities(query) { count += 1 }
    #expect(count == 1)
    
    // Add entity with new archetype combination
    world.createEntity(Position(x: 2, y: 2), Velocity(dx: 1, dy: 1))
    
    // Cache should be invalidated, should find both
    count = 0
    for _ in world.entities(query) { count += 1 }
    #expect(count == 2)
}

@Test func testUnregisterQuery() {
    let world = World()
    world.createEntity(Position(x: 1, y: 1))
    
    let query = Query(with: Position.self)
    world.register(query)
    #expect(world.isRegistered(query))
    
    world.unregister(query)
    #expect(!world.isRegistered(query))
    
    // entities() still works (just slower without cache)
    var count = 0
    for _ in world.entities(query) { count += 1 }
    #expect(count == 1)
}

@Test func testEntitiesWithoutRegistration() {
    let world = World()
    world.createEntity(Position(x: 1, y: 1))
    world.createEntity(Position(x: 2, y: 2))
    
    // entities() works without registration (just no caching)
    let query = Query(with: Position.self)
    var sum = 0.0
    for entity in world.entities(query) {
        sum += entity[Position.self]!.x
    }
    
    #expect(sum == 3.0)
}

@Test func testDumpString() {
    let world = World()
    world.createEntity(Position(x: 10, y: 20))
    world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))

    let dump = world.dumpString()

    #expect(dump.contains("World Dump:"))
    #expect(dump.contains("Position"))
    #expect(dump.contains("Velocity"))
    #expect(dump.contains("Total Entities: 2"))
}

@Test func testStatsDescription() {
    let world = World()
    world.createEntity(Position(x: 0, y: 0))

    let stats = world.stats
    let description = stats.description

    #expect(description.contains("Entities: 1"))
    #expect(description.contains("Archetypes:"))
}
