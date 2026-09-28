internal enum ParallelExecutor {
    @concurrent
    static func run(_ jobs: [ParallelJob], limit: Int) async -> [ParallelJobResult] {
        await withTaskGroup(of: (Int, ParallelJobResult).self) { group in
            var results: [ParallelJobResult?] = Array(repeating: nil, count: jobs.count)
            var next = 0
            for _ in 0..<min(limit, jobs.count) {
                let index = next
                let job = jobs[index]
                group.addTask { (index, await job.execute()) }
                next += 1
            }
            for await (index, result) in group {
                results[index] = result
                if next < jobs.count {
                    let index = next
                    let job = jobs[index]
                    group.addTask { (index, await job.execute()) }
                    next += 1
                }
            }
            return results.map {
                guard let result = $0 else {
                    preconditionFailure("A structured parallel job did not complete")
                }
                return result
            }
        }
    }
}
