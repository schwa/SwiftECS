/// The policy for merging deferred commands between systems in a run.
public enum PipelineSynchronization: Hashable, Sendable {
    /// Merges pending commands only before a system whose inputs they affect.
    case automatic
    /// Merges pending commands after every system.
    case afterEachSystem
}
