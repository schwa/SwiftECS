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
    func update(world: World, deltaTime: Double) {
        world.forEachMutable(Position.self, Velocity.self) { _, pos, vel in
            pos.x += vel.dx * deltaTime
            pos.y += vel.dy * deltaTime
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
