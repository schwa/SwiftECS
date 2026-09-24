public protocol Relationship {
    static var isExclusive: Bool { get }
    static var isAcyclic: Bool { get }
}

extension Relationship {
    public static var isExclusive: Bool { false }
    public static var isAcyclic: Bool { false }
}
