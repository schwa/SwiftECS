import ECS

// MARK: - Test Components

struct Position: Component {
    var x: Double
    var y: Double
}

struct Velocity: Component {
    var dx: Double
    var dy: Double
}

struct Health: Component {
    var current: Int
}

// MARK: - Test Systems

struct MovementSystem: System {
    static let query = Query(with: Position.self, Velocity.self)

    func initialize(world: World) {
        world.register(Self.query)
    }

    func update(world: World, deltaTime: Double) {
        for entity in world.entities(matching: Self.query) {
            entity[Position.self]!.x += entity[Velocity.self]!.dx * deltaTime
            entity[Position.self]!.y += entity[Velocity.self]!.dy * deltaTime
        }
    }
}

struct InitializableMovementSystem: System {
    func initialize(world _: World) { /* intentionally empty */ }
    func update(world _: World, deltaTime _: Double) { /* intentionally empty */ }
}

struct CleanupMovementSystem: System {
    func update(world _: World, deltaTime _: Double) { /* intentionally empty */ }
    func cleanup(world _: World) { /* intentionally empty */ }
}
