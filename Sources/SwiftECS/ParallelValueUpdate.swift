@usableFromInline
internal struct ParallelValueUpdate: Sendable {
    let apply: @Sendable () -> Void
}
