@testable import SwiftECS
import Testing

private func signature(_ types: ComponentType...) -> ArchetypeSignature {
    ArchetypeSignature(Set(types))
}

@Test func `emptied intermediate archetype is reclaimed on component add`() {
    let world = World()
    let base = world.archetypes.count
    let entity = world.createEntity(Position(x: 0, y: 0))
    #expect(world.archetypes.count == base + 1)
    entity.set(Velocity(dx: 1, dy: 0))
    // The now-empty {Position} archetype is gone; the {Position, Velocity} one remains.
    #expect(world.archetypes[signature(ComponentType(Position.self))] == nil)
    #expect(world.archetypes[signature(ComponentType(Position.self), ComponentType(Velocity.self))] != nil)
    #expect(world.archetypes.count == base + 1)
    // Results are unchanged.
    #expect(world.snapshot(with: Position.self).map(\.id) == [entity.id])
    #expect(world.snapshot(with: Velocity.self).map(\.id) == [entity.id])
}

@Test func `emptied intermediate archetype is reclaimed on component remove`() {
    let world = World()
    let base = world.archetypes.count
    let entity = world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    entity.remove(Velocity.self)
    // {Position, Velocity} emptied and reclaimed; entity now lives in {Position}.
    #expect(world.archetypes[signature(ComponentType(Position.self), ComponentType(Velocity.self))] == nil)
    #expect(world.archetypes[signature(ComponentType(Position.self))] != nil)
    #expect(world.archetypes.count == base + 1)
    #expect(world.snapshot(with: Position.self).map(\.id) == [entity.id])
}

@Test func `the base empty archetype is retained and reused`() {
    let world = World()
    #expect(world.archetypes.count == 1)
    let empty = world.createEntity()
    empty.set(Health(current: 1))
    // The base empty-signature archetype is emptied but kept, alongside {Health}.
    #expect(world.archetypes.count == 2)
    #expect(world.snapshot(with: Health.self).map(\.id) == [empty.id])
    // A new component-less entity reuses the retained base rather than recreating it.
    let another = world.createEntity()
    #expect(world.archetypes.count == 2)
    #expect(world[another.id] != nil)
}

@Test func `destroying the last entity reclaims its archetype`() throws {
    let world = World()
    let base = world.archetypes.count
    let entity = world.createEntity(Position(x: 0, y: 0), Health(current: 1))
    #expect(world.archetypes.count == base + 1)
    try world.destroy(entity)
    #expect(world.archetypes[signature(ComponentType(Position.self), ComponentType(Health.self))] == nil)
    #expect(world.archetypes.count == base)
    #expect(world.snapshot(with: Position.self).isEmpty)
}

@Test func `only-empty archetypes are reclaimed, not ones that still hold entities`() {
    let world = World()
    let keep = world.createEntity(Position(x: 0, y: 0))
    let move = world.createEntity(Position(x: 1, y: 1))
    move.set(Velocity(dx: 1, dy: 0))
    // {Position} still holds `keep`, so it is not reclaimed.
    #expect(world.archetypes[signature(ComponentType(Position.self))] != nil)
    #expect(world.snapshot(with: Position.self).map(\.id).sorted { $0 < $1 } == [keep.id, move.id].sorted { $0 < $1 })
}

@Test func `registered queries stay correct across reclamation`() {
    let world = World()
    let query = Query(with: Position.self)
    world.register(query)
    let entity = world.createEntity(Position(x: 0, y: 0))
    #expect(world.snapshot(matching: query).map(\.id) == [entity.id])
    entity.set(Velocity(dx: 1, dy: 0))
    // {Position} reclaimed, entity now in {Position, Velocity}; the registered query still matches.
    #expect(world.snapshot(matching: query).map(\.id) == [entity.id])
    entity.remove(Position.self)
    // {Position, Velocity} reclaimed; the query no longer matches.
    #expect(world.snapshot(matching: query).isEmpty)
}

@Test func `a captured lazy sequence survives reclamation of its archetype`() {
    let world = World()
    let entity = world.createEntity(Position(x: 0, y: 0))
    let sequence = world.entities(matching: Query(with: Position.self))
    entity.set(Velocity(dx: 1, dy: 0))
    // The {Position} archetype was emptied and reclaimed, but the captured sequence
    // holds it directly, so iterating is safe and now yields nothing.
    #expect(Array(sequence).isEmpty)
    // A fresh sequence sees the entity via its new archetype.
    #expect(world.entities(matching: Query(with: Position.self)).map(\.id) == [entity.id])
}
