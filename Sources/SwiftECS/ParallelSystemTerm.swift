public protocol ParallelSystemTerm: SystemTerm, Sendable where ComponentValue: ConcurrentComponent {}

extension Read: ParallelSystemTerm where Value: ConcurrentComponent {}
extension Write: ParallelSystemTerm where Value: ConcurrentComponent {}
