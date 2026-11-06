/// The built-in parent relationship. The source is the child and the target is the parent.
///
/// Each entity has at most one parent, and hierarchies cannot contain cycles.
public enum ChildOf: ConcurrentRelationship {
    public static var isExclusive: Bool { true }
    public static var isAcyclic: Bool { true }
}
