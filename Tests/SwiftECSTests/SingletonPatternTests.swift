import SwiftECS
import Testing

// Documents the recommended pattern for issue #18: singletons are an
// application-owned well-known entity, not a library API. These tests use only
// existing API and also pin down the query-visibility tradeoff that argues
// against a library-level entity-backed singleton.

private struct GameConfig: Component, Equatable {
    var difficulty: Int
    var seed: UInt64
}

@Test func `a well-known entity models a singleton`() throws {
    let world = World()
    let singleton = world.createEntity(GameConfig(difficulty: 2, seed: 42)).id

    // Type-keyed read via the retained id; uniqueness is the app holding one id.
    #expect(world[singleton]?.get(GameConfig.self)?.values == GameConfig(difficulty: 2, seed: 42))

    world[singleton]?.set(GameConfig(difficulty: 5, seed: 7))
    #expect(world[singleton]?.get(GameConfig.self)?.values == GameConfig(difficulty: 5, seed: 7))

    _ = try world.destroy(world[singleton]!)
    #expect(world[singleton] == nil)
}

@Test func `an entity-backed singleton is visible to ordinary queries`() {
    let world = World()
    _ = world.createEntity(GameConfig(difficulty: 1, seed: 0))
    // The hazard a library API would inherit: a singleton stored as an ordinary
    // component appears in query results and counts like any other entity.
    #expect(world.snapshot(with: GameConfig.self).count == 1)
}
