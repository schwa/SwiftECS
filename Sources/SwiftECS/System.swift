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
extension System {
    /// Default empty implementation.
    public func initialize(world _: World) {}
    /// Default empty implementation.
    public func cleanup(world _: World) {}
}
