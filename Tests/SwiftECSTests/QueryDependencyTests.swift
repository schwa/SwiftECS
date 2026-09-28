@testable import SwiftECS
import Testing

private struct DisabledForSync: Component {}
private enum SyncLink: Relationship {}

@Test func `matching dependencies include typed terms compound exclusions and traversal`() throws {
    let root = EntityID()
    let filter = Query((!.contains(DisabledForSync.self) || .contains(Health.self)) && .descendant(of: root, via: SyncLink.self))
    let access = SystemQuery(Read<Position>(), matching: filter).binding.access
    let dependency = try #require(access.queries.first)
    #expect(dependency.components == [ComponentType(Position.self), ComponentType(DisabledForSync.self), ComponentType(Health.self)])
    #expect(dependency.relationships == [RelationshipType(SyncLink.self)])
    #expect(access.reads == [ComponentType(Position.self)])
    #expect(access.writes.isEmpty)
    #expect(EditComponent<DisabledForSync>().binding.access.commandEffects.requiresMerge(before: access))
    #expect(EditRelationship<SyncLink>().binding.access.commandEffects.requiresMerge(before: access))
    #expect(!EditRelationship<ChildOf>().binding.access.commandEffects.requiresMerge(before: access))
}

private final class MutableQueryInput: SystemInput {
    var requiresHealth = true

    var binding: SystemBinding<SystemRows<Read<Position>>> {
        SystemQuery(Read<Position>(), matching: requiresHealth ? Query(with: Health.self) : .all).binding
    }
}

@Test func `system bindings cannot drift from their declared matching dependencies`() throws {
    let world = World()
    world.createEntity(Position(x: 0, y: 0))
    let input = MutableQueryInput()
    var count = 0
    let system = System("frozen").run(input) { _, rows in count = rows.count { _ in true } }
    input.requiresHealth = false
    try world.run(system, deltaTime: 0)
    #expect(count == 0)
    #expect(system.access.queries.first?.components.contains(ComponentType(Health.self)) == true)
}

@Test func `creation dependencies evaluate whole signatures and negative predicates`() {
    let position = CreateEntities(Position.self).binding.access.commandEffects
    let empty = CreateEntities().binding.access.commandEffects
    let healthy = CreateEntities(Position.self, Health.self).binding.access.commandEffects
    let moving = SystemQuery(Read<Position>(), Read<Velocity>()).binding.access
    #expect(!position.requiresMerge(before: moving))
    #expect(!empty.requiresMerge(before: moving))
    #expect(!healthy.requiresMerge(before: moving))
    let excluded = SystemQuery(Read<Position>(), matching: Query.all.without(Health.self)).binding.access
    #expect(position.requiresMerge(before: excluded))
    #expect(!healthy.requiresMerge(before: excluded))
    let negative = SystemQuery(matching: Query.all.without(Health.self)).binding.access
    #expect(empty.requiresMerge(before: negative))
    #expect(!healthy.requiresMerge(before: negative))
    #expect(empty.requiresMerge(before: SystemQuery().binding.access))
    #expect(!empty.requiresMerge(before: SystemQuery(matching: .none).binding.access))
}

@Test func `pending creation signatures remain separate rather than forming a fictitious archetype`() {
    var effects = CreateEntities(Position.self).binding.access.commandEffects
    effects.merge(CreateEntities(Velocity.self).binding.access.commandEffects)
    #expect(effects.creationSignatures.count == 2)
    #expect(!effects.requiresMerge(before: SystemQuery(Read<Position>(), Read<Velocity>()).binding.access))
    effects.merge(EditComponent<Velocity>().binding.access.commandEffects)
    #expect(effects.requiresMerge(before: SystemQuery(Read<Position>(), Read<Velocity>()).binding.access))
}

@Test func `relationship predicates remain conservative under negation and disjunction`() {
    let relationship = QueryPredicate.relationship(RelationshipType(SyncLink.self), nil)
    let filter = Query(!relationship || .contains(Health.self))
    let dependency = SystemQuery(Read<Position>(), matching: filter).binding.access
    #expect(CreateEntities(Position.self).binding.access.commandEffects.requiresMerge(before: dependency))
    #expect(EditRelationship<SyncLink>().binding.access.commandEffects.requiresMerge(before: dependency))
    #expect(!CreateEntities(Health.self).binding.access.commandEffects.requiresMerge(before: dependency))
}

@Test func `deferred edits conflict with immediate writes but do not merge just to queue another edit`() {
    let pending = EditComponent<Health>().binding.access
    let immediate = SystemQuery(Write<Health>()).binding.access
    #expect(pending.conflicts(with: immediate))
    #expect(immediate.conflicts(with: pending))
    #expect(pending.conflicts(with: pending))
    #expect(!pending.commandEffects.requiresMerge(before: pending))
    #expect(!pending.conflicts(with: SystemQuery(Read<Position>()).binding.access))
}
