import SwiftECS
import Testing

// MARK: - Additional Test Components

struct Enemy: Component {}
struct Flying: Component {}
struct Poisoned: Component {}

// MARK: - Query Tests

@Suite("Query Tests")
struct QueryTests {
    // MARK: - Basic Predicate Tests

    @Test("QueryPredicate.all matches everything")
    func testPredicateAll() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))
        world.createEntity()

        let results = world.snapshot(matching: Query(.all))
        #expect(results.count == 3)
    }

    @Test("QueryPredicate.none matches nothing")
    func testPredicateNone() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))

        let results = world.snapshot(matching: Query(.none))
        #expect(results.count == 0)
    }

    @Test("QueryPredicate.has matches entities with component")
    func testPredicateHas() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))
        world.createEntity(Position(x: 1, y: 1), Velocity(dx: 0, dy: 0))

        let results = world.snapshot(matching: Query(.contains(Position.self)))
        #expect(results.count == 2)
    }

    // MARK: - NOT Tests

    @Test("NOT predicate excludes entities")
    func testNotPredicate() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))
        world.createEntity(Position(x: 1, y: 1), Velocity(dx: 0, dy: 0))

        let query = Query(!.contains(Position.self))
        let results = world.snapshot(matching: query)
        #expect(results.count == 1)
        // Should only have entity with just Velocity
        #expect(results[0].contains(Velocity.self))
        #expect(!results[0].contains(Position.self))
    }

    @Test("Double negation simplifies")
    func testDoubleNegation() {
        let predicate: QueryPredicate = !(!.contains(Position.self))
        #expect(predicate == .contains(ComponentType(Position.self)))
    }

    @Test("NOT all equals none")
    func testNotAllEqualsNone() {
        let predicate: QueryPredicate = !.all
        #expect(predicate == .none)
    }

    @Test("NOT none equals all")
    func testNotNoneEqualsAll() {
        let predicate: QueryPredicate = !.none
        #expect(predicate == .all)
    }

    // MARK: - AND Tests

    @Test("AND predicate requires all components")
    func testAndPredicate() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))
        world.createEntity(Position(x: 1, y: 1), Velocity(dx: 0, dy: 0))
        world.createEntity(Position(x: 2, y: 2), Velocity(dx: 1, dy: 1), Health(current: 100))

        let query = Query(.contains(Position.self) && .contains(Velocity.self))
        let results = world.snapshot(matching: query)
        #expect(results.count == 2)
    }

    @Test("AND with all is identity")
    func testAndWithAll() {
        let predicate: QueryPredicate = .contains(Position.self) && .all
        #expect(predicate == .contains(ComponentType(Position.self)))
    }

    @Test("AND with none is none")
    func testAndWithNone() {
        let predicate: QueryPredicate = .contains(Position.self) && .none
        #expect(predicate == .none)
    }

    @Test("AND flattens nested ANDs")
    func testAndFlattening() {
        let p1: QueryPredicate = .contains(Position.self) && .contains(Velocity.self)
        let p2: QueryPredicate = p1 && .contains(Health.self)
        if case let .and(predicates) = p2 {
            #expect(predicates.count == 3)
        } else {
            Issue.record("Expected flattened AND predicate")
        }
    }

    // MARK: - OR Tests

    @Test("OR predicate matches either component")
    func testOrPredicate() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))
        world.createEntity(Health(current: 50))
        world.createEntity()

        let query = Query(.contains(Position.self) || .contains(Velocity.self))
        let results = world.snapshot(matching: query)
        #expect(results.count == 2)
    }

    @Test("OR with none is identity")
    func testOrWithNone() {
        let predicate: QueryPredicate = .contains(Position.self) || .none
        #expect(predicate == .contains(ComponentType(Position.self)))
    }

    @Test("OR with all is all")
    func testOrWithAll() {
        let predicate: QueryPredicate = .contains(Position.self) || .all
        #expect(predicate == .all)
    }

    @Test("OR flattens nested ORs")
    func testOrFlattening() {
        let p1: QueryPredicate = .contains(Position.self) || .contains(Velocity.self)
        let p2: QueryPredicate = p1 || .contains(Health.self)
        if case let .or(predicates) = p2 {
            #expect(predicates.count == 3)
        } else {
            Issue.record("Expected flattened OR predicate")
        }
    }

    // MARK: - Complex Query Tests

    @Test("Complex query: has A AND NOT B")
    func testComplexQueryAndNot() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0), Enemy())
        world.createEntity(Position(x: 1, y: 1))
        world.createEntity(Velocity(dx: 1, dy: 1), Enemy())

        // Entities with Position but NOT Enemy
        let query = Query(.contains(Position.self) && !.contains(Enemy.self))
        let results = world.snapshot(matching: query)
        #expect(results.count == 1)
        #expect(results[0].contains(Position.self))
        #expect(!results[0].contains(Enemy.self))
    }

    @Test("Complex query: (A OR B) AND C")
    func testComplexQueryOrAnd() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0), Health(current: 100))
        world.createEntity(Velocity(dx: 1, dy: 1), Health(current: 50))
        world.createEntity(Position(x: 1, y: 1))
        world.createEntity(Velocity(dx: 0, dy: 0))
        world.createEntity(Health(current: 25))

        // Entities with (Position OR Velocity) AND Health
        let query = Query((.contains(Position.self) || .contains(Velocity.self)) && .contains(Health.self))
        let results = world.snapshot(matching: query)
        #expect(results.count == 2)
    }

    @Test("Complex query: flying enemies or poisoned units")
    func testComplexQueryGameScenario() {
        let world = World()
        // Flying enemy
        world.createEntity(Position(x: 0, y: 0), Enemy(), Flying())
        // Ground enemy
        world.createEntity(Position(x: 1, y: 1), Enemy())
        // Poisoned ally
        world.createEntity(Position(x: 2, y: 2), Poisoned())
        // Healthy ally
        world.createEntity(Position(x: 3, y: 3))
        // Flying ally
        world.createEntity(Position(x: 4, y: 4), Flying())

        // Flying enemies OR poisoned units
        let query = Query((.contains(Enemy.self) && .contains(Flying.self)) || .contains(Poisoned.self))
        let results = world.snapshot(matching: query)
        #expect(results.count == 2)
    }

    // MARK: - Query Builder Tests

    @Test("Query.with adds component requirement")
    func testQueryWith() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Position(x: 1, y: 1), Velocity(dx: 0, dy: 0))

        let query = Query.all.with(Position.self).with(Velocity.self)
        let results = world.snapshot(matching: query)
        #expect(results.count == 1)
    }

    @Test("Query.without excludes component")
    func testQueryWithout() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Position(x: 1, y: 1), Enemy())

        let query = Query.all.with(Position.self).without(Enemy.self)
        let results = world.snapshot(matching: query)
        #expect(results.count == 1)
        #expect(!results[0].contains(Enemy.self))
    }

    @Test("Query.and combines queries")
    func testQueryAnd() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0), Health(current: 100))
        world.createEntity(Position(x: 1, y: 1))
        world.createEntity(Health(current: 50))

        let q1 = Query(with: Position.self)
        let q2 = Query(with: Health.self)
        let results = world.snapshot(matching: q1.and(q2))
        #expect(results.count == 1)
    }

    @Test("Query.or combines queries")
    func testQueryOr() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))
        world.createEntity(Health(current: 50))

        let q1 = Query(with: Position.self)
        let q2 = Query(with: Velocity.self)
        let results = world.snapshot(matching: q1.or(q2))
        #expect(results.count == 2)
    }

    @Test("Query.negated inverts query")
    func testQueryNegated() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))

        let query = Query(with: Position.self).negated
        let results = world.snapshot(matching: query)
        #expect(results.count == 1)
        #expect(results[0].contains(Velocity.self))
    }

    // MARK: - Variadic Query Initializer Tests

    @Test("Query with variadic component types")
    func testQueryVariadic() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1), Health(current: 100))
        world.createEntity(Position(x: 1, y: 1), Velocity(dx: 0, dy: 0))
        world.createEntity(Position(x: 2, y: 2))

        let results = world.snapshot(with: Position.self, Velocity.self)
        #expect(results.count == 2)
    }

    @Test("Query with single component type")
    func testQuerySingle() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))
        world.createEntity(Velocity(dx: 1, dy: 1))

        let results = world.snapshot(with: Position.self)
        #expect(results.count == 1)
    }

    // MARK: - Edge Cases

    @Test("Empty world returns empty results")
    func testEmptyWorld() {
        let world = World()
        let results = world.snapshot(matching: Query(.contains(Position.self)))
        #expect(results.count == 0)
    }

    @Test("Query static constructors")
    func testQueryStaticConstructors() {
        let world = World()
        world.createEntity(Position(x: 0, y: 0))

        #expect(world.snapshot(matching: Query.all).count == 1)
        #expect(world.snapshot(matching: Query.none).count == 0)
    }
}
