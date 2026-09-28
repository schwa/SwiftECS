@testable import SwiftECS
import Testing

@Test func `system terms determine matching and writable fields`() throws {
    let world = World()
    let matching = world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
    let excluded = world.createEntity(Position(x: 10, y: 20))
    let system = System("move").query(Write<Position>(), Read<Velocity>()).each { context, position, velocity in
        position.value.x += velocity.dx * context.deltaTime
    }
    let entity = try world.addSystem(system)
    try world.update(deltaTime: 2)
    #expect(matching[Position.self]?.x == 7)
    #expect(excluded[Position.self]?.x == 10)
    #expect(entity[SystemDescriptor.self]?.access?.reads == [ComponentType(Position.self), ComponentType(Velocity.self)])
    #expect(entity[SystemDescriptor.self]?.access?.writes == [ComponentType(Position.self)])
}

@Test func `multiple queries preserve independent matching and union access`() throws {
    let world = World()
    let position = world.createEntity(Position(x: 1, y: 0))
    world.createEntity(Health(current: 10))
    let positions = SystemQuery(Write<Position>())
    let health = SystemQuery(Read<Health>())
    let system = System("multiple").run(positions, health) { _, positions, health in
        let total = health.reduce(0) { $0 + $1.fields.current }
        for row in positions {
            row.fields.value.x += Double(total)
        }
    }
    try world.addSystem(system)
    try world.update(deltaTime: 0)
    #expect(position[Position.self]?.x == 11)
    #expect(system.access.writes == [ComponentType(Position.self)])
    #expect(system.access.reads.contains(ComponentType(Health.self)))
}

@Test func `commands flush between systems and support newly created relationship endpoints`() throws {
    let world = World()
    let original = world.createEntity(Health(current: 1))
    var created: EntityID?
    let spawn = System("spawn").run(SystemQuery(Read<Health>()), Commands()) { _, rows, commands in
        created = try commands.create(Health(current: 2))
        let child = try commands.create(Health(current: 3))
        commands.addRelationship(ChildOf.self, from: child, to: created!)
        for row in rows {
            commands.destroy(row.entityID)
        }
        #expect(rows.count { _ in true } == 1)
        #expect(world[created!] == nil)
    }
    var seen: [Int] = []
    let read = System("read").query(Read<Health>()).each { _, health in seen.append(health.current) }
    try world.addSystem(spawn)
    try world.addSystem(read, after: [spawn.id])
    try world.update(deltaTime: 1)
    #expect(!original.exists)
    #expect(seen.sorted() == [2, 3])
    #expect(world[created!]?.children.count == 1)
    #expect(spawn.access.changesStructure)
}

private final class ReferenceComponent: Component {}

@Test func `invalid terms fail registration without side effects`() throws {
    let world = World()
    let reference = System("reference").query(Read<ReferenceComponent>()).each { _, _ in }
    #expect(throws: SystemError.referenceComponent(ComponentType(ReferenceComponent.self))) {
        try world.addSystem(reference)
    }
    let duplicate = System("duplicate").query(Read<Health>(), Write<Health>()).each { _, _, _ in }
    #expect(throws: SystemError.duplicateTerm(ComponentType(Health.self))) {
        try world.addSystem(duplicate)
    }
    #expect(world.entityCount == 0)
}

@Test func `access conflicts do not invent execution order`() throws {
    let reader = System("read").query(Read<Position>()).each { _, _ in }
    let writer = System("write").query(Write<Position>()).each { _, _ in }
    #expect(!reader.access.conflicts(with: reader.access))
    #expect(reader.access.conflicts(with: writer.access))
    #expect(writer.access.conflicts(with: reader.access))
    let world = World()
    try world.addSystem(reader)
    try world.addSystem(writer)
    #expect(try world.systemExecutionOrder == [reader.id, writer.id])
}

private enum CallbackFailure: Error { case failed }

@Test func `throwing callbacks invalidate references and discard pending commands`() throws {
    let world = World()
    world.createEntity(Health(current: 1))
    var retained: SystemComponent<Health>?
    let system = System("failure").run(SystemQuery(Write<Health>()), Commands()) { _, rows, commands in
        retained = rows.first { _ in true }?.fields
        try commands.create(Position(x: 0, y: 0))
        throw CallbackFailure.failed
    }
    try world.addSystem(system)
    #expect(throws: CallbackFailure.self) { try world.update(deltaTime: 1) }
    #expect(retained?.scope.isActive == false)
    #expect(world.snapshot(with: Position.self).isEmpty)
}

@Test func `system writes survive observer driven archetype changes`() throws {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
    let token = world.observe(Position.self) { _ in entity.set(Health(current: 1)) }
    defer { world.removeObserver(token) }
    try world.addSystem(System("write").query(Write<Position>(), Write<Velocity>()).each { _, position, velocity in
        position.value.x = 10
        velocity.value.dx = 20
    })
    try world.update(deltaTime: 1)
    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Velocity.self]?.dx == 20)
}
