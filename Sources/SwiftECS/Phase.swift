/// A component that marks an entity as a scheduling phase.
///
/// Create phases with ``World/createPhase(_:after:)``. Systems join a phase through ``InPhase``, and phases order each
/// other through ``DependsOn``.
public struct Phase: Component {
    /// The display name of the phase.
    public var name: String

    /// Creates a phase with the given name.
    public init(_ name: String) {
        self.name = name
    }
}
