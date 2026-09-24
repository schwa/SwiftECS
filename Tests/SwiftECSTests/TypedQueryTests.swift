import Observation
import SwiftECS
import Testing

// Observation callbacks execute synchronously on the test thread.
private final class TypedQueryChanges: @unchecked Sendable {
    var count = 0
    let read: () -> Void

    init(_ read: @escaping () -> Void) {
        self.read = read
        observe()
    }

    private func observe() {
        withObservationTracking(read) { [weak self] in
            guard let self else {
                return
            }
            count += 1
            observe()
        }
    }
}

@Test func `typed queries read and write multiple archetypes without optional access`() throws {
    let world = World()
    let first = world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
    let second = world.createEntity(Position(x: 5, y: 6), Velocity(dx: 7, dy: 8), Health(current: 100))
    let excluded = world.createEntity(Position(x: 9, y: 10))
    var visited = Set<EntityID>()
    for row in world.query(Position.self, Velocity.self) {
        var (position, velocity) = row.values
        position.x += velocity.dx
        row.set(position, velocity)
        visited.insert(row.entityID)
    }
    #expect(visited == [first.id, second.id])
    #expect(first[Position.self]?.x == 4)
    #expect(second[Position.self]?.x == 12)
    #expect(excluded[Position.self]?.x == 9)
    #expect(Array(world.query(Position.self, Velocity.self)).count == 2)
}

@Test func `copied typed iterators and rows keep independent indices`() throws {
    let world = World()
    let first = world.createEntity(Position(x: 1, y: 0))
    let second = world.createEntity(Position(x: 2, y: 0))
    var iterator = world.query(Position.self).makeIterator()
    let firstResult = iterator.next()
    let firstRow = try #require(firstResult)
    var copy = iterator
    let secondResult = iterator.next()
    let copiedSecondResult = copy.next()
    let secondRow = try #require(secondResult)
    let copiedSecondRow = try #require(copiedSecondResult)
    #expect(firstRow.entityID == first.id)
    #expect(secondRow.entityID == second.id)
    #expect(copiedSecondRow.entityID == second.id)
    firstRow.set(Position(x: 10, y: 0))
    copiedSecondRow.set(Position(x: 20, y: 0))
    #expect(firstRow.values.x == 10)
    #expect(secondRow.values.x == 20)
    let end = iterator.next()
    let copiedEnd = copy.next()
    #expect(end == nil)
    #expect(copiedEnd == nil)
}

@Test func `typed queries support zero one three and four component packs`() throws {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4), Health(current: 5), Transform(x: 6, y: 7, z: 8))
    let single = try #require(world.query(Health.self).first { _ in true })
    single.set(Health(current: 20))
    #expect(single.values.current == 20)
    let triple = try #require(world.query(Position.self, Velocity.self, Health.self).first { _ in true })
    triple.set(Position(x: 10, y: 20), Velocity(dx: 30, dy: 40), Health(current: 50))
    #expect(triple.values.2.current == 50)
    let four = try #require(world.query(Position.self, Velocity.self, Health.self, Transform.self).first { _ in true })
    four.set(Position(x: 11, y: 21), Velocity(dx: 31, dy: 41), Health(current: 51), Transform(x: 61, y: 71, z: 81))
    #expect(entity[Transform.self]?.z == 81)
    let emptyPack = try #require(world.query().first { _ in true })
    let changes = TypedQueryChanges { _ = world.entityCount }
    emptyPack.set()
    #expect(changes.count == 0)
    #expect(emptyPack.entityID == entity.id)
}

@Test func `typed queries combine predicates with required columns and registered caches`() throws {
    let world = World()
    let query = Query(.not(.contains(Health.self)))
    world.register(query)
    world.createEntity(Health(current: 1))
    #expect(Array(world.query(Position.self, matching: query)).isEmpty)
    let entity = world.createEntity(Position(x: 1, y: 2))
    world.createEntity(Velocity(dx: 1, dy: 2))
    #expect(Array(world.query(Position.self, matching: query)).map(\.entityID) == [entity.id])
    entity.set(Health(current: 2))
    #expect(Array(world.query(Position.self, matching: query)).isEmpty)
    entity.remove(Health.self)
    #expect(Array(world.query(Position.self, matching: query)).count == 1)
    #expect(Array(world.query(Position.self, matching: .none)).isEmpty)
    try world.destroy(entity)
    #expect(Array(world.query(Position.self)).isEmpty)
}

@Test func `typed query reads track empty results sequences iterators and rows`() throws {
    let world = World()
    let empty = TypedQueryChanges { _ = world.query(Position.self) }
    let entity = world.createEntity(Position(x: 1, y: 2))
    #expect(empty.count == 1)
    let sequence = world.query(Position.self)
    let row = try #require(sequence.first { _ in true })
    let reads: [() -> Void] = [
        { _ = sequence.makeIterator() },
        { var iterator = sequence.makeIterator(); _ = iterator.next() },
        { _ = row.values }
    ]
    for read in reads {
        let changes = TypedQueryChanges(read)
        entity.set(Position(x: 3, y: 4))
        #expect(changes.count == 1)
        row.set(Position(x: 5, y: 6))
        #expect(changes.count == 2)
    }
}

private struct TypedMovementSystem: System {
    func update(world: World, deltaTime: Double) {
        for row in world.query(Position.self, Velocity.self) {
            var (position, velocity) = row.values
            position.x += velocity.dx * deltaTime
            row.set(position, velocity)
        }
    }
}

@Test func `typed writes preserve component events and batch storage notifications`() throws {
    let world = World()
    for _ in 0..<1_000 {
        world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    }
    var positionEvents = 0
    var velocityEvents = 0
    let positionToken = world.observe(Position.self) { _ in positionEvents += 1 }
    let velocityToken = world.observe(Velocity.self) { _ in velocityEvents += 1 }
    let changes = TypedQueryChanges { _ = world.query(Position.self) }
    try world.addSystem(TypedMovementSystem())
    try world.update(deltaTime: 1)
    #expect(positionEvents == 1_000)
    #expect(velocityEvents == 1_000)
    #expect(changes.count == 1)
    #expect(world.query(Position.self).allSatisfy { $0.values.x == 1 })
    world.removeObserver(positionToken)
    world.removeObserver(velocityToken)
}
