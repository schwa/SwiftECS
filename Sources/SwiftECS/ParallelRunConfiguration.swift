internal struct ParallelRunConfiguration {
    let deltaTime: Double
    let advancesTime: Bool
    let synchronization: PipelineSynchronization
    let parallelism: Int
}
