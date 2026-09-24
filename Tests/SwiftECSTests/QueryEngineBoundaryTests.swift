import Observation
import SwiftECS
import Testing

private enum QueryLink: Relationship {}

private struct QueryExpectation {
    let predicate: QueryPredicate
    let matches: (Entity) -> Bool
}

private func queryExpectations(root: Entity) -> [QueryExpectation] {
    let leaves: [QueryExpectation] = [
        QueryExpectation(predicate: .all) { _ in true },
        QueryExpectation(predicate: .none) { _ in false },
        QueryExpectation(predicate: .contains(Health.self)) { $0.contains(Health.self) },
        QueryExpectation(predicate: .contains(Position.self)) { $0.contains(Position.self) },
        QueryExpectation(predicate: .related(QueryLink.self, to: root.id)) { $0.hasRelationship(QueryLink.self, to: root) },
        QueryExpectation(predicate: .descendant(of: root.id, via: QueryLink.self)) {
            $0.ancestors(via: QueryLink.self).contains { $0.id == root.id }
        }
    ]
    var cases = leaves
    cases.append(QueryExpectation(predicate: .and([])) { _ in true })
    cases.append(QueryExpectation(predicate: .or([])) { _ in false })
    for leaf in leaves {
        cases.append(QueryExpectation(predicate: .not(leaf.predicate)) { !leaf.matches($0) })
    }
    for left in leaves {
        for right in leaves {
            cases.append(QueryExpectation(predicate: .and([left.predicate, right.predicate])) { left.matches($0) && right.matches($0) })
            cases.append(QueryExpectation(predicate: .or([left.predicate, right.predicate])) { left.matches($0) || right.matches($0) })
            cases.append(QueryExpectation(predicate: .not(.and([left.predicate, .not(right.predicate)]))) { !left.matches($0) || right.matches($0) })
        }
    }
    return cases
}

private func verifyQueryPaths(_ cases: [QueryExpectation], in world: World) {
    for testCase in cases {
        let query = Query(testCase.predicate)
        let expected = world.entities.filter(testCase.matches)
        let ids = Set(expected.map(\.id))
        let healthIDs = Set(expected.filter { $0.contains(Health.self) }.map(\.id))
        let bothIDs = Set(expected.filter { $0.contains(Health.self) && $0.contains(Position.self) }.map(\.id))
        #expect(Set(world.snapshot(matching: query).map(\.id)) == ids)
        #expect(Set(world.entities(matching: query).map(\.id)) == ids)
        #expect(Set(world.query(matching: query).map(\.entityID)) == ids)
        #expect(Set(world.query(Health.self, matching: query).map(\.entityID)) == healthIDs)
        #expect(Set(world.query(Position.self, Health.self, matching: query).map(\.entityID)) == bothIDs)
        #expect(Set(world.snapshot(matching: query).map(\.id)) == ids)
    }
}

@Test(arguments: [false, true])
private func `query paths agree through graph edits archetype changes and registration cycles`(registered: Bool) throws {
    let world = World()
    let root = world.createEntity()
    let child = world.createEntity(Health(current: 1))
    let leaf = world.createEntity(Position(x: 0, y: 0))
    world.createEntity(Health(current: 2), Position(x: 1, y: 1))
    let cases = queryExpectations(root: root)
    if registered {
        for testCase in cases { world.register(Query(testCase.predicate)) }
    }
    verifyQueryPaths(cases, in: world)
    try child.addRelationship(QueryLink.self, to: root)
    try leaf.addRelationship(QueryLink.self, to: child)
    verifyQueryPaths(cases, in: world)
    world.createEntity(Health(current: 3), Velocity(dx: 1, dy: 2))
    child.remove(Health.self)
    leaf.set(Health(current: 4))
    verifyQueryPaths(cases, in: world)
    try child.removeRelationship(QueryLink.self, to: root)
    try world.destroy(root)
    verifyQueryPaths(cases, in: world)
    for testCase in cases { world.unregister(Query(testCase.predicate)) }
    verifyQueryPaths(cases, in: world)
    for testCase in cases { world.register(Query(testCase.predicate)) }
    verifyQueryPaths(cases, in: world)
}

@Test func `registered selections preserve captured archetypes and discover new ones on recreation`() {
    let world = World()
    let query = Query(with: Health.self)
    world.register(query)
    #expect(world.snapshot(matching: query).isEmpty)
    let first = world.createEntity(Health(current: 1))
    let snapshot = world.snapshot(matching: query)
    let lazy = world.entities(matching: query)
    let typed = world.query(Health.self, matching: query)
    let newArchetype = world.createEntity(Health(current: 2), Position(x: 0, y: 0))
    let sameArchetype = world.createEntity(Health(current: 3))
    #expect(snapshot.map(\.id) == [first.id])
    #expect(Set(lazy.map(\.id)) == [first.id, sameArchetype.id])
    #expect(Set(typed.map(\.entityID)) == [first.id, sameArchetype.id])
    let all = Set([first.id, sameArchetype.id, newArchetype.id])
    #expect(Set(world.snapshot(matching: query).map(\.id)) == all)
    #expect(Set(world.entities(matching: query).map(\.id)) == all)
    #expect(Set(world.query(Health.self, matching: query).map(\.entityID)) == all)
}

// The observation callback executes synchronously on the test thread.
private final class QueryInvalidation: @unchecked Sendable {
    var changed = false
}

@Test func `query registrations are world local and do not invalidate storage observers`() {
    let first = World()
    let second = World()
    let query = Query(with: Health.self)
    let entity = first.createEntity(Health(current: 1))
    first.register(query)
    #expect(first.snapshot(matching: query).map(\.id) == [entity.id])
    #expect(!second.isRegistered(query))
    second.register(query)
    #expect(second.snapshot(matching: query).isEmpty)
    let invalidation = QueryInvalidation()
    withObservationTracking {
        _ = first.query(Health.self, matching: query)
    } onChange: {
        invalidation.changed = true
    }
    first.unregister(query)
    first.register(query)
    second.createEntity(Health(current: 2), Position(x: 0, y: 0))
    #expect(!invalidation.changed)
    #expect(first.snapshot(matching: query).map(\.id) == [entity.id])
    entity.set(Health(current: 3))
    #expect(invalidation.changed)
}
