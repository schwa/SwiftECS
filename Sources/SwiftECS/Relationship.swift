/// A type that names a kind of link between two entities.
///
/// Relationship types carry no payload. Conform an empty enum to declare one:
///
///     enum Likes: Relationship {}
public protocol Relationship {
    /// Whether a source can link to at most one target. Adding a new link replaces the old one.
    static var isExclusive: Bool { get }
    /// Whether adding a link that makes a cycle throws ``RelationshipError/cycleDetected(_:)``.
    static var isAcyclic: Bool { get }
}

extension Relationship {
    /// By default, a source can link to many targets.
    public static var isExclusive: Bool { false }
    /// By default, cycles are allowed.
    public static var isAcyclic: Bool { false }
}
