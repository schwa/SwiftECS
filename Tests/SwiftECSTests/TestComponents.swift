import SwiftECS

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

func movementSystem() -> System {
    System("MovementSystem").query(Write<Position>(), Read<Velocity>()).each { context, position, velocity in
        var value = position.value
        value.x += velocity.dx * context.deltaTime
        value.y += velocity.dy * context.deltaTime
        position.value = value
    }
}

func initializableMovementSystem() -> System {
    System("InitializableMovementSystem").onInitialize { /* intentionally empty */ }
}

func cleanupMovementSystem() -> System {
    System("CleanupMovementSystem").onCleanup { /* intentionally empty */ }
}
