import ECS
import Testing

@Test func `snapshots freeze membership while lazy queries see matching rows at iteration`() throws {
    let world = World()
    let first = world.createEntity(Health(current: 1))
    let predicate = Query(with: Health.self)
    let snapshot = world.snapshot(matching: predicate)
    let handles = world.entities(matching: predicate)
    let rows = world.query(Health.self, matching: predicate)
    let second = world.createEntity(Health(current: 2))
    first.set(Health(current: 3))
    #expect(snapshot.map(\.id) == [first.id])
    #expect(snapshot.first?[Health.self]?.current == 3)
    #expect(Set(handles.map(\.id)) == [first.id, second.id])
    #expect(Set(rows.map(\.entityID)) == [first.id, second.id])
    for entity in snapshot {
        try world.destroy(entity)
    }
    #expect(second.exists)
    #expect(!first.exists)
    #expect(world.snapshot(with: Health.self).map(\.id) == [second.id])
}
