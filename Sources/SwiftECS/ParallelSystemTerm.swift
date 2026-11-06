/// A query term that parallel systems can use. ``Read`` and ``Write`` conform when the component is a
/// ``ConcurrentComponent``.
public protocol ParallelSystemTerm: SystemTerm, Sendable where ComponentValue: ConcurrentComponent {}

extension Read: ParallelSystemTerm where Value: ConcurrentComponent {}
extension Write: ParallelSystemTerm where Value: ConcurrentComponent {}
