# Parallel Systems

Run eligible systems across tasks with compile-time race checks.

## Parallel systems and entity iteration

Parallel execution is opt-in. `ConcurrentComponent` combines the existing value-semantics contract with `Sendable` and marks data as eligible for workers.
Ordinary `Component` types remain supported by serial systems. Direct class components remain invalid system inputs.

```swift
struct Particle: ConcurrentComponent {
    var x: Double
    var speed: Double
}

let particleMovement = System("particles")
    .query(Write<Particle>())
    .eachParallel(minimumRowsPerTask: 256) { context, row in
        var particle = row.fields.value
        particle.x += particle.speed * context.deltaTime
        row.fields.value = particle
    }

try world.addSystem(particleMovement)
world.createEntity(Particle(x: 0, speed: 1))

@MainActor func advance(_ world: World) async throws {
    try await world.update(deltaTime: 1.0 / 60, parallelism: 4)
}
```

`System.runParallel(inputs...)` and `.query(...).runParallel` declare one eligible callback per system.
The async runner groups independent callbacks while preserving conflicts, phases, explicit dependencies, and the captured schedule.
The concurrency limit bounds active jobs across the entire group, not separately for each system.

`.eachParallel` partitions one query into disjoint row ranges across its matching archetypes.
Its callback receives `SystemContext`, a typed `SystemRow`, and any declared command capabilities.
Empty queries launch no jobs. Small queries use fewer partitions according to `minimumRowsPerTask`.
By default, the query has one partition per worker. `tasksPerWorker` splits the query into up to `parallelism * tasksPerWorker` partitions. `minimumRowsPerTask` still limits the partition size. More partitions let the worker pool balance uneven per-row work. Without them, all workers wait for the slowest range. Each row is still covered once, each writable row has one owner, and commands merge in prepared order. The default value of one keeps one partition per worker.

```swift
struct Trail: ConcurrentComponent { let source: EntityID }

let trailSystem = System("trails").query(Read<Particle>())
    .eachParallel(CreateEntities(Trail.self), minimumRowsPerTask: 128) { _, row, creator in
        try creator.create(Trail(source: row.entityID))
    }
```

Each partition can access only its own rows and declared commands. Additional queries belong in a whole-system `runParallel` callback, not a partitioned callback.
Callback order across rows is unspecified. Order-dependent state and reductions require a serial callback or separately synchronized, order-independent logic.
Commands retain prepared row order within a partitioned system, regardless of task completion order.

All parallel callbacks are synchronous `@Sendable` closures. Captures must satisfy Swift concurrency checking, including actor isolation.
Typed creation and component-edit payloads must conform to `ConcurrentComponent`.
Parallel relationship tags use `ConcurrentRelationship`, which requires a transferable metatype without transferring relationship instances.
`ChildOf`, `DependsOn`, and `InPhase` support this contract. Typed destruction is also supported.
Unrestricted `Commands()` is serial-only. Parallel bindings carry their own serial fallback and metadata, so preparation cannot change declared access.

`World`, `System`, query rows, and writable references are not `Sendable`. Workers receive task-local views, never a world handle.
World columns remain lock-protected. Workers read snapshots and edit task-owned buffers, without per-element column or bookkeeping locks.
Partitions copy only their selected rows. Overlapping queries within a whole-system callback share one buffer per column.
After jobs join, dirty values are written back before dependent systems or structural commands run.
The buffers and owner-local lifetime cells are not Sendable. Only immutable update payloads cross back to the owner.
Only the lock-protected implementation types require `@unchecked Sendable`. Worlds and callbacks do not.
Raw ECS APIs do not become thread-safe. References cannot escape into another task. They expire when their owning system callback or partition finishes.

**Ownership during an async run:** the world remains on its calling actor or task.
While workers run, live storage reads, writes, and observer changes through raw APIs fail an ownership precondition.
Concurrent or nested run calls on that world throw `SystemError.parallelRunInProgress`.
Async runs also reject nesting inside an active synchronous run. The synchronous runner retains its existing nested-run behavior.

Serial-only callbacks execute on the owner between worker groups. Component observers force serial fallback and retain synchronous delivery, including reentrant component mutations.
Storage observation publishes on the owner after workers finish. Structural merges, cleanup, and world reuse occur only after all jobs join.
A callback shared between worlds still needs thread-safe captured state and explicit application ordering when its external effects interact.

Existing synchronous `world.update` and `world.run` remain serial, including eligible systems.
The async overloads of `update` and every `run` form accept a positive `parallelism` limit. A limit of one uses serial execution.
`parallelBatchCount` and `parallelTaskCount` supplement the existing run statistics. They count groups and total jobs, not dedicated threads.

## Parallel failures and cancellation

Cancellation is cooperative. The runner checks it at execution boundaries, and partitioned iteration checks it before each row.
Long whole-system callbacks must call `Task.checkCancellation()` themselves if they need prompt interruption.
The runner always joins its own jobs before returning. It does not forcibly terminate callbacks.

If a group contains failures, its jobs finish before the lowest logical system/partition error is reported. Later groups do not start.
Worker edits are written back after joining, including edits from failed callbacks and siblings. There is no rollback.
Serial callbacks still write immediately and retain synchronous observer behavior.
Only command batches from the successful system prefix before the failed system are retained.
One failed partition discards all commands from that system. Reservations from discarded batches are released without applying those commands.
Successful batches merge in schedule order, never completion order. An earlier merge failure takes precedence over a later callback failure.

