import SwiftECS

struct FallingObject: ConcurrentComponent {
    enum Kind: Sendable {
        case star, meteor
    }

    var kind: Kind
}
