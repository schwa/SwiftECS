/// Timing information passed to every system callback.
public struct SystemContext: Sendable {
    /// The time step for this run, in seconds.
    public let deltaTime: Double
    /// The world's simulation time when the run started.
    public let simulationTime: Double
}
