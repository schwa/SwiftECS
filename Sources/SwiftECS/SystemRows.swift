public struct SystemRows<each Term: SystemTerm>: Sequence {
    internal let terms: (repeat each Term)
    internal let storage: [SystemQueryStorage<repeat (each Term).ComponentValue>]
    internal let scope: SystemScope
    internal let revision: UInt64

    public func makeIterator() -> SystemRowIterator<repeat each Term> {
        scope.checkActive()
        // Explicit expansion avoids a Swift 6.4 pack-forwarding compiler crash.
        return SystemRowIterator<repeat each Term>(terms: (repeat each terms), storage: storage, scope: scope, revision: revision)
    }
}
