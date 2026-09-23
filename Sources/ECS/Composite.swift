/// A variadic container for bundling multiple values using parameter packs.
public struct Composite<each T> {
    /// The contained values.
    public let values: (repeat each T)

    /// Create a composite from variadic values.
    public init(_ values: repeat each T) {
        self.values = (repeat each values)
    }
}

/// Equatable conformance when all elements are Equatable.
extension Composite: Equatable where repeat each T: Equatable {
    /// Returns true if all corresponding elements are equal.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in repeat (each lhs.values, each rhs.values) {
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
        for value in repeat (each values) {
            value.hash(into: &hasher)
        }
    }
}

/// Sendable conformance when all elements are Sendable.
extension Composite: Sendable where repeat each T: Sendable {
}

extension Composite: Comparable where repeat each T: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in repeat (each lhs.values, each rhs.values) {
            guard left < right else {
                return false
            }
        }
        return true
    }
}
