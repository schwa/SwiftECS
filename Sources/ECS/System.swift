/// Logic that operates on entities.
public protocol System {
    /// Called each frame to update entity state.
    func update(world: World, deltaTime: Double)
    /// Called when the system is added to the world.
    func initialize(world: World)
    /// Called when the system is removed from the world.
    func cleanup(world: World)
}

/// Default implementations for optional lifecycle methods.
public extension System {
    /// Default empty implementation.
    func initialize(world: World) {}
    /// Default empty implementation.
    func cleanup(world: World) {}
}
