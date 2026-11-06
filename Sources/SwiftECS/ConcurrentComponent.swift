/// A component that parallel systems can read and write from worker tasks.
public protocol ConcurrentComponent: Component, Sendable {}
