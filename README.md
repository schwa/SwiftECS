# SwiftECS

The package requires Swift 6.2 or later. Declared Apple deployment targets are macOS 14 and iOS 26 or later.

## Usage

### Components and entities

```swift
import SwiftECS

struct Position: Component {
    var x: Double
    var y: Double
}

struct Velocity: Component {
    var x: Double
    var y: Double
}

struct Health: Component {
    var current: Int
}
struct Disabled: Component {}

let world = World()
let player = world.createEntity(
    Position(x: 0, y: 0),
    Velocity(x: 1, y: 0),
    Health(current: 100)
)
let empty = world.createEntity()

let id = player.id
let found = world[id]                  // Entity?
let exists = player.exists
let count = world.entityCount
let entities = world.entities
```

### Read and change components

```swift
let position = player[Position.self]   // Position?
let hasHealth = player.contains(Health.self)

player[Position.self] = Position(x: 10, y: 20)
player.set(Health(current: 80))
player.set(Position(x: 0, y: 0), Velocity(x: 2, y: 1))

if let components = player.get(Position.self, Velocity.self) {
    let (position, velocity) = components.values
    player.set(Composite(position, velocity))
}

let removed = player.remove(Health.self) // Health?
player[Disabled.self] = nil

let copy = try world.clone(player)         // Entity?
if let copy {
    try world.destroy(copy)
}
try world.destroy(empty)
```

### Build queries

```swift
let moving = Query(with: Position.self, Velocity.self)
let active = moving.without(Disabled.self)
let healthy = Query(with: Health.self)

let both = active.and(healthy)
let either = active.or(healthy)
let excluded = active.negated
let positions = Query.all.with(Position.self)
let nothing = Query.none

let predicate = Query(
    .contains(Position.self) &&
    (.contains(Velocity.self) || .contains(Health.self)) &&
    !QueryPredicate.contains(Disabled.self)
)

let matches = world.snapshot(matching: active)      // [Entity]
let withHealth = world.snapshot(with: Health.self)
```

### Iterate and update

`query` is the typed, lazy path. Component references support selective writes without optional lookups.

```swift
let deltaTime = 1.0 / 60

for row in world.query(Position.self, Velocity.self, matching: active) {
    let (position, velocity) = row.components
    var updated = position.value
    updated.x += velocity.value.x * deltaTime
    updated.y += velocity.value.y * deltaTime
    position.value = updated          // Only Position emits a change event
    let id = row.entityID
}

for row in world.query(Health.self) {
    let health = row.components        // A single reference, not a tuple
    health.value.current += 1
}

for row in world.query(Position.self, Velocity.self) {
    let (position, velocity) = row.values
    row.set(position, velocity)        // Whole-row write emits events for both
}

for entity in world.entities(matching: active) {
    let position = entity[Position.self]
}
```

`entities(matching:)` lazily returns handles. `snapshot` returns an array of handles with fixed membership, not frozen component values.

Do not create or destroy entities, or add or remove component types, during lazy or typed iteration. Collect handles first:

```swift
let doomed = world.snapshot(with: Disabled.self)
for entity in doomed {
    try world.destroy(entity)
}
```

Query rows and component references are not safe across structural changes. Recreate lazy sequences to include new archetypes.

### Cache repeated queries

Registration caches matching archetypes, not component values or relationship results.

```swift
world.register(active)
let registered = world.isRegistered(active)

for row in world.query(Position.self, Velocity.self, matching: active) {
    let (position, velocity) = row.values
}

world.unregister(active)
```

### Run systems

A system combines typed queries with a callback, following the [Flecs systems model](https://www.flecs.dev/flecs/md_docs_2Systems.html).

```swift
let movement = System("movement")
    .query(Write<Position>(), Read<Velocity>(), matching: Query.all.without(Disabled.self))
    .each { context, position, velocity in
        var value = position.value
        value.x += velocity.x * context.deltaTime
        value.y += velocity.y * context.deltaTime
        position.value = value
    }

let regeneration = System("regeneration")
    .query(Write<Health>())
    .each { _, health in
        health.value.current = min(100, health.value.current + 1)
    }

try world.addSystem(movement)
try world.addSystem(regeneration, after: [movement.id])
try world.update(deltaTime: 1.0 / 60)

let access = movement.access
let order = try world.systemExecutionOrder
try world.run(movement, deltaTime: 1.0 / 60)
world.removeAllSystems()
```

`Read<T>` supplies a value. `Write<T>` supplies a writable reference to an existing component.
Query terms determine matching, callback types, and access metadata. Duplicate component types within one query throw during registration.
Callbacks receive time information, not a `World` or unrestricted `Entity` handle.

System components must have value semantics. Registration rejects direct class components.
Nested references must also behave as values. Swift cannot prove deep immutability.
Callbacks must not capture world or entity handles to bypass their declared access.
The API is an access contract, not a sandbox for arbitrary Swift closures.

`access.reads` includes writable components because `Write<T>` permits reads and writes.
`access.queries` records complete matching predicates, including exclusions and relationship traversal, separately from component-value access.
`access.commandEffects` describes permitted creation signatures, component edits, relationship edits, and destruction.
Bindings are captured when a system is defined, so execution uses the same declarations as its metadata.
`access.conflicts(with:)` reports conflicts but does not infer execution order or enable parallel execution.
Phases and explicit dependencies still determine order.

### Multiple queries and deferred commands

```swift
let health = SystemQuery(Read<Health>())
let positions = SystemQuery(Write<Position>())
let expire = System("expire").run(health, positions, DestroyEntities()) { _, health, positions, commands in
    for row in health where row.fields.current <= 0 {
        commands.destroy(row.entityID)
    }
    for row in positions {
        row.fields.value.y += 1
    }
}

let spawn = System("spawn").run(CreateEntities(Position.self), EditRelationship<ChildOf>()) { _, entities, parents in
    let parent = try entities.create(Position(x: 0, y: 0))
    let child = try entities.create(Position(x: 1, y: 1))
    parents.add(from: child, to: parent)
}
```

Each query has independent matching. `row.fields` contains the declared outputs in term order, and `row.entityID` identifies the entity.
A single term produces one field rather than a tuple.
`.query(...).run` receives all matching rows once. `.each` invokes its callback for each matching row.
`System("clock").run { context in ... }` runs once without a query, even in an empty world.

Command inputs grant specific capabilities:

- `CreateEntities(Position.self, Velocity.self)` permits only that creation signature. `CreateEntities()` permits empty entities.
- `EditComponent<Health>()` permits deferred `.set(value, on: id)` and `.remove(from: id)` for `Health` only.
- `EditRelationship<ChildOf>()` permits `.add(from:to:)` and `.remove(from:to:)` for `ChildOf` only.
- `DestroyEntities()` permits destruction, including removal of arbitrary components and incoming or outgoing relationships.
- `Commands()` retains unrestricted creation, component edits, destruction, and relationship edits as a conservative fallback.

Commands accept entity IDs, never unrestricted handles. New IDs can serve as targets in later commands.
Creation signatures reject direct class components and duplicate component types. A creator cannot accept different component types or omit a declared component.
Destruction and component removal are no-ops for absent targets. Component assignment to an absent entity throws when the command executes.
Relationship commands validate their endpoints and constraints when they execute.

Rows have fixed membership for one callback. Iteration reads the current component values and skips entities with missing required components.
Write handles and row sequences expire when the callback returns. Retaining them does not extend their lifetime.
Writes publish component events immediately and batch storage observation through the existing mutation scope.
Commands remain private until their callback succeeds. New entities do not enter that callback's queries.
If a callback throws, its commands are discarded and earlier successful callbacks' pending commands flush before the error propagates.
Immediate component writes remain applied. If that final flush also fails, its error takes precedence over the callback error.
If a command throws during a flush, earlier commands remain applied and the remaining commands are discarded.

Lifecycle hooks use `.onInitialize { ... }` and `.onCleanup { ... }` for captured system state, without world access.
Registration throws on duplicate IDs. Manual `world.run(system, deltaTime:)` validates inputs but does not register the system or call lifecycle hooks.
`update` advances simulation time before execution and throws for invalid schedules or callback errors.

### Phases and pipelines

Systems and phases are entities. `DependsOn` relationships order them, and pipelines select systems through queries.

```swift
struct Gameplay: Component {}

let physics = try world.createPhase("Physics")
let recovery = try world.createPhase("Recovery", after: [physics])
try world.addSystem(movement, id: "move", phase: physics).set(Gameplay())
try world.addSystem(regeneration, id: "recover", phase: recovery).set(Gameplay())

let gameplay = world.createEntity(Pipeline(Query(with: Gameplay.self)))
try world.run(gameplay, deltaTime: 1.0 / 60)
world.defaultPipeline = Pipeline(Query(with: Gameplay.self))
try world.update(deltaTime: 1.0 / 60)
```

`run` does not advance simulation time. `update` runs `defaultPipeline` and advances time after validation.
Each run captures its schedule before execution. Runtime changes affect the next run.
Explicit system dependencies outside the selection throw an error. Phase dependencies never select additional systems.
Ready systems run in registration order.

System entities appear in normal queries and entity counts. `systemCount` counts registered systems only.
`systemExecutionOrder` now requires `try` because invalid schedules throw instead of returning stale results.
See [Phases and pipelines](Experiments/PhasesAndPipelines.md) for lifecycle, observation, and deletion rules.

### Synchronization points

The default `.automatic` policy retains commands across unrelated systems. It merges pending effects before a dependent system binds its inputs.
The decision considers effects from all command-producing callbacks since the previous merge, including complete creation signatures, component edits, exclusions, and relationship dependencies.
Immediate component writes do not require a merge unless earlier deferred commands affect their inputs. Access conflicts never change execution order.

Unrestricted commands and destruction retain conservative barriers. Component observers also force per-system flushing because their callbacks can have undeclared effects.
Every run flushes its remaining commands before returning. Empty buffers do not count as merges.

```swift
let automatic = Pipeline(Query(with: Gameplay.self))
let conservative = Pipeline(Query(with: Gameplay.self), synchronization: .afterEachSystem)
try world.run(automatic, deltaTime: 1.0 / 60)
let statistics = world.lastRunStatistics
```

`lastRunStatistics` reports attempted systems, nonempty merges, and attempted commands for the most recent completed run, including execution failures.
The statistics are not observable. Invalid schedules do not start a run or replace the previous statistics.

Nested runs merge completed outer callbacks before schedule selection. The active callback's private commands remain pending until that callback succeeds.
During observer reentrancy, a nested run drains the remaining commands from the current merge before its own execution.
A caught reentrant flush error still aborts the owning merge. Cleanup waits until the outermost run finishes.

Synchronization alone does not authorize concurrent callbacks. Parallel execution requires the separate eligibility contract below.
Captured world access remains outside the declared-access contract, except for explicit nested runs in the synchronous runner.

The opt-in `SynchronizationPerformanceTests` compares `.automatic` with `.afterEachSystem` using identical commands and final-state checks:

```sh
ECS_RUN_SYNC_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter SynchronizationPerformanceTests
```

The initial 32-producer measurement reduced merges from 32 to 1 for 4,096 commands per frame.
Median frame time was 4.06 ms automatically versus 3.99 ms per-system. Fewer merges did not improve runtime in this workload.

### Parallel systems and entity iteration

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
Only the lock-protected implementation types require `@unchecked Sendable`; worlds and callbacks do not.
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

### Parallel failures and cancellation

Cancellation is cooperative. The runner checks it at execution boundaries, and partitioned iteration checks it before each row.
Long whole-system callbacks must call `Task.checkCancellation()` themselves if they need prompt interruption.
The runner always joins its own jobs before returning. It does not forcibly terminate callbacks.

If a group contains failures, its jobs finish before the lowest logical system/partition error is reported. Later groups do not start.
Worker edits are written back after joining, including edits from failed callbacks and siblings. There is no rollback.
Serial callbacks still write immediately and retain synchronous observer behavior.
Only command batches from the successful system prefix before the failed system are retained.
One failed partition discards all commands from that system. Reservations from discarded batches are released without applying those commands.
Successful batches merge in schedule order, never completion order. An earlier merge failure takes precedence over a later callback failure.

### Parallel validation and measurements

Starfall movement and collision opt into parallel eligibility. Its stateful spawner and Survival stages retain serial fallback.
Demo UI ticks remain synchronous because their views read the live world. Async UI simulation needs isolated render snapshots, tracked separately in issue #15.

```sh
fish Scripts/check-concurrency.fish
xcb test SwiftECS/SwiftECS -- --sanitize thread
ECS_RUN_PARALLEL_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter ParallelPerformanceTests
```

The compile checks cover unsafe captures, actor isolation, payloads, unrestricted commands, and escaped write handles.
Tests cover bounded overlap, shared reads, separate-column writes, partitions, deterministic command order, cancellation, observers, ownership, and cleanup.

Release measurements after the profiling fixes on Apple M5 Max, macOS 27.0, Swift 6.4 used 4,096 entities and two runs:

| Workload | Serial ms/frame | Four-job limit ms/frame |
| --- | ---: | ---: |
| Independent compute | 9.67–9.75 | 2.91–3.01 |
| Partitioned compute | 2.44–2.47 | 1.10 |
| Memory-bound | 0.64 | 0.58–0.78 |
| Conflicting systems | 9.63–9.81 | 9.88–10.04 |
| Command-heavy | 16.20–16.27 | 17.02–17.03 |
| Empty callbacks | 0.014–0.016 | 0.41–0.43 |

The benchmark also covers 64 entities and limits of one and two. A limit of one measures the synchronous reference runner.
Parallel execution helps these compute-heavy cases, but can add overhead to small, conflicting, and command-heavy workloads.
The memory-bound case shows little benefit at this size. There is no automatic workload tuning or lock-free World storage claim.

A direct 100,000-entity movement comparison uses the original XYZ arithmetic and three component writes per entity.
Each mode has three warm-up frames, 60 measured frames, and three rotated rounds. Every entity is verified after each sample.

| Movement path | Before profiling fixes | After fixes, ms/frame |
| --- | ---: | ---: |
| Original raw component-reference loop | 17.25 | 14.68 |
| Typed system, serial | 77.28 | 12.50 |
| Typed system, 2 jobs | 153.46 | 10.56 |
| Typed system, 4 jobs | 116.59 | 7.97 |
| Typed system, 8 jobs | 153.46 | 6.45 |

The system modes use the same `.eachParallel` callback, with `Read<Physics>` supplying a value per row.
The raw baseline retains its original component-reference access. Eight jobs are about 1.94 times faster than the corrected typed serial path.
See [the profiling report](Experiments/ParallelMovementProfiling.md) for evidence, ownership details, and reproduction commands.

```sh
ECS_RUN_MOVEMENT_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter MovementParallelBenchmarkTests
```

### Link entities

Relationships have no payload. They allow multiple targets and cycles unless their type restricts them.

```swift
enum Likes: Relationship {}

enum EquippedBy: Relationship {
    static var isExclusive: Bool { true }
    static var isAcyclic: Bool { true }
}

let friend = world.createEntity()
let weapon = world.createEntity()

try player.addRelationship(Likes.self, to: friend)
try weapon.addRelationship(EquippedBy.self, to: player)

let liked = player.targets(of: Likes.self)
let admirers = friend.sources(of: Likes.self)
let linked = player.hasRelationship(Likes.self, to: friend)
let equipmentOwners = weapon.ancestors(via: EquippedBy.self)
let equipment = player.descendants(via: EquippedBy.self)

try player.removeRelationship(Likes.self, to: friend)
```

Exclusive relationships replace the previous target. Acyclic relationships reject cycles. Writes reject dead entities and cross-world links with `RelationshipError`.

### Hierarchies and deletion

`ChildOf` allows one parent and rejects cycles. Traversal is breadth-first, excludes the starting entity, and visits each entity once.

```swift
let parent = world.createEntity()
let child = world.createEntity()
let grandchild = world.createEntity()

try child.setParent(parent)
try grandchild.setParent(child)

let currentParent = child.parent
let children = parent.children
let ancestors = grandchild.ancestors()
let descendants = parent.descendants()

try child.setParent(nil)               // Detach
try child.setParent(parent)            // Reparent

try world.destroy(parent)                 // Children survive as roots
try world.destroyRecursively(child)       // Delete child and grandchild
try world.destroyRecursively(player, following: EquippedBy.self)
```

Deletion removes all incoming and outgoing links. Cloning copies outgoing links with their original targets, but does not clone descendants.

Lifecycle methods throw `WorldError.foreignEntity` for a handle from another world. For stale handles, `destroy` returns `false`, `clone` returns `nil`, and recursive deletion returns `0`. Neither case mutates storage.

### Query relationships

```swift
let owner = world.createEntity()
let projectile = world.createEntity(Position(x: 0, y: 0))
try projectile.setParent(owner)

let directChildren = Query(.related(ChildOf.self, to: owner.id))
let hasParent = Query(.related(ChildOf.self))
let roots = Query(!QueryPredicate.related(ChildOf.self))
let subtree = Query(.descendant(of: owner.id))
let equipped = Query(.descendant(of: owner.id, via: EquippedBy.self))

for row in world.query(Position.self, matching: directChildren) {
    let position = row.values
}
```

Relationship predicates work with every query API. Lazy queries check current links during iteration. Descendant queries exclude their root and do not imply traversal order.

### Observe component events

```swift
var events: [ComponentEvent<Health>] = []
let token = world.observe(Health.self) { event in
    events.append(event)               // .added, .changed, or .removed
}

owner.set(Health(current: 100))
owner.set(Health(current: 90))
owner.remove(Health.self)
world.removeObserver(token)
```

Callbacks run synchronously. Typed writes also emit component events. These events are separate from Swift Observation and do not describe relationships.

### Use SwiftUI observation

```swift
import SwiftUI

@MainActor
struct EntityCountView: View {
    @State private var world = World()

    var body: some View {
        VStack {
            Text("Entities: \(world.entityCount)")
            Button("Add entity") {
                world.createEntity(Position(x: 0, y: 0))
            }
        }
    }
}
```

Component, query, and relationship reads establish world-wide observation dependencies. Writes inside one outermost `world.update()` produce one storage invalidation. Writes outside updates notify immediately.

`World` is not thread-safe. Keep SwiftUI-owned worlds on the main actor. Internal mutations of reference-type components require an ECS write to notify observation.

### Inspect storage

```swift
let types = owner.componentTypes
let components = owner.allComponents
let typeName = ComponentType(Health.self).name

let stats = world.stats
let summary = world.dumpString()
let detail = world.dumpDetailed()
```
