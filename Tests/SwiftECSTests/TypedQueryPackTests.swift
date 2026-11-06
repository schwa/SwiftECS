@testable import SwiftECS
import Testing

private enum PackProbeError: Error {
    case missingEntity
    case missingColumn
}

private func probeColumn<Value: Component>(_ type: Value.Type, in archetype: Archetype) throws -> Column<Value> {
    guard let column = archetype.columns[ComponentType(type)] as? Column<Value> else {
        throw PackProbeError.missingColumn
    }
    return column
}

private func probeValue<Value: Component>(_ column: Column<Value>, at index: Int) -> Value {
    column.value(at: index)
}

// This is a compiler feasibility probe, not a proposed public query API.
private struct TypedQueryPackProbe<each Value: Component> {
    let world: World
    let entityID: EntityID
    let index: Int
    let columns: (repeat Column<each Value>)

    init(world: World, entityID: EntityID, index: Int, columns: repeat Column<each Value>) {
        self.world = world
        self.entityID = entityID
        self.index = index
        self.columns = (repeat each columns)
    }

    var values: (repeat each Value) {
        get {
            world.trackStorageAccess()
            // Direct array subscripting inside this expansion fails as of Swift 6.4.
            return (repeat probeValue(each columns, at: index))
        }
        nonmutating set {
            set(repeat each newValue)
        }
    }

    func set(_ values: repeat each Value) {
        world.mutations.perform({
            for (column, value) in repeat (each columns, each values) {
                column.setValue(value, at: index)
            }
        }, events: {
            for value in repeat each values {
                world.notifyChanged(entityID: entityID, component: value)
            }
        })
    }
}

// swiftlint:disable unused_parameter
private func makePackProbe<each Value: Component>(world: World, entity: Entity, types: repeat (each Value).Type) throws -> TypedQueryPackProbe<repeat each Value> {
    guard let location = world.entityLocations[entity.id], let archetype = world.archetypes[location.signature] else {
        throw PackProbeError.missingEntity
    }
    let columns = (repeat try probeColumn((each Value).self, in: archetype))
    return TypedQueryPackProbe(world: world, entityID: entity.id, index: location.index, columns: repeat each columns)
}
// swiftlint:enable unused_parameter

@Test func `parameter packs retain typed ECS columns and write through tuple access`() throws {
    let world = World()
    let untouched = world.createEntity(Position(x: 0, y: 0), Velocity(dx: 0, dy: 0))
    let entity = world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
    let reference = try makePackProbe(world: world, entity: entity, types: Position.self, Velocity.self)
    #expect(reference.values.0.x == 1)
    #expect(reference.values.1.dy == 4)
    var changes = 0
    let token = world.observe(Position.self) { _ in changes += 1 }
    reference.values = (Position(x: 10, y: 20), Velocity(dx: 30, dy: 40))
    #expect(entity[Position.self]?.x == 10)
    #expect(entity[Velocity.self]?.dy == 40)
    #expect(untouched[Position.self]?.x == 0)
    #expect(changes == 1)
    entity.set(Position(x: 50, y: 60))
    #expect(reference.values.0.x == 50)
    world.removeObserver(token)
}

@Test func `parameter packs support one three and four component columns`() throws {
    let world = World()
    let entity = world.createEntity(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4), Health(current: 5), Transform(x: 6, y: 7, z: 8))
    let single = try makePackProbe(world: world, entity: entity, types: Health.self)
    #expect(single.values.current == 5)
    single.set(Health(current: 9))
    #expect(entity[Health.self]?.current == 9)
    let triple = try makePackProbe(world: world, entity: entity, types: Position.self, Velocity.self, Health.self)
    #expect(triple.values.2.current == 9)
    let four = try makePackProbe(world: world, entity: entity, types: Position.self, Velocity.self, Health.self, Transform.self)
    four.values = (Position(x: 10, y: 20), Velocity(dx: 30, dy: 40), Health(current: 50), Transform(x: 60, y: 70, z: 80))
    #expect(entity[Transform.self]?.z == 80)
    #expect(triple.values.2.current == 50)
}

@Test func `parameter pack column binding rejects absent components`() {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0))
    #expect(throws: PackProbeError.self) {
        _ = try makePackProbe(world: world, entity: entity, types: Position.self, Velocity.self)
    }
}
