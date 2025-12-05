/// A variadic container for bundling multiple values using parameter packs.
public struct Composite<each T> {
    private let children: (repeat each T)

    /// Create a composite from variadic values.
    public init(_ children: repeat each T) {
        self.children = (repeat each children)
    }
}

/// Equatable conformance when all elements are Equatable.
extension Composite: Equatable where repeat each T: Equatable {
    /// Returns true if all corresponding elements are equal.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in repeat (each lhs.children, each rhs.children) {
            guard left == right else {
                return false
            }
        }
        return true
    }
}

/// Hashable conformance when all elements are Hashable.
extension Composite: Hashable where repeat each T: Hashable {
    /// Hashes all elements into the hasher.
    public func hash(into hasher: inout Hasher) {
        for child in repeat (each children) {
            child.hash(into: &hasher)
        }
    }
}

/// Sendable conformance when all elements are Sendable.
extension Composite: Sendable where repeat each T: Sendable {
}
