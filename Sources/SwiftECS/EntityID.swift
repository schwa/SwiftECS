#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Unique entity identifier.
public struct EntityID: Hashable, Equatable, Sendable {
    /// The underlying integer value.
    public let value: UInt64

    /// Create a new random entity ID.
    public init() {
        var value: UInt64 = 0
        withUnsafeMutableBytes(of: &value) { buffer in
            arc4random_buf(buffer.baseAddress!, buffer.count)
        }
        self.value = value
    }
}

extension EntityID: Comparable {
    public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
        lhs.value < rhs.value
    }
}

extension EntityID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(UInt64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
