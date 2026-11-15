import Observation

/// A world that takes part in Swift Observation.
///
/// Reads through ``world``, its entities, and its queries establish observation dependencies.
/// Keep an observable world on the actor that owns its views.
public final class ObservableWorld: Observable {
    /// The observed world.
    public let world: World

    /// Create an empty observed world.
    public init() {
        world = World(isObserved: true)
    }
}
