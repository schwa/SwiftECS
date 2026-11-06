/// A scheduling relationship from a system to the phase it runs in. A system belongs to one phase.
public enum InPhase: ConcurrentRelationship {
    public static var isExclusive: Bool { true }
}
