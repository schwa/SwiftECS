# Systems

Run logic over queries with phases, pipelines, and deferred commands.

## Run systems

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

## Multiple queries and deferred commands

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

## Phases and pipelines

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

Pause is application-owned: `World` has no run loop, so an application pauses by not calling `update`, which already freezes `simulationTime`. To keep some systems running while gameplay is paused, run a selective pipeline with `run(_:deltaTime:)` (which does not advance time) instead of `update`. Direct component and relationship writes remain available while paused, so pause menus, upgrades, and restarts work without a library pause flag.
Explicit system dependencies outside the selection throw an error. Phase dependencies never select additional systems.
Ready systems run in registration order.

System entities appear in normal queries and entity counts. `systemCount` counts registered systems only.

Singletons are application-owned. Model global state as one well-known entity whose id the application retains, then read it with `world[id]?.get(_:)`. There is no library singleton API: an entity-backed singleton is stored as an ordinary component, so it appears in `query`/`snapshot` results and entity counts like any other entity, and uniqueness is the application's responsibility. A dedicated API would either inherit that query-visibility surprise or require a separate non-entity store, so it is intentionally left to the application.
`systemExecutionOrder` now requires `try` because invalid schedules throw instead of returning stale results.
Registration without an explicit phase uses a lazily created `Update` phase. There is no fixed engine phase list.
`before:`, `after:`, and `dependencies:` permit forward references. Later registration reuses the unresolved entity, which does not count toward `systemCount`.
Phase ordering includes transitive paths through empty phases. Dependency cycles can exist during editing, but a run rejects invalid reachable schedules before execution.
Cycle diagnostics can include blocked dependents outside the cycle itself.

`SystemDescriptor` is World-owned registration metadata. Do not copy, replace, or remove it directly.
Destroying a system removes its registration and calls cleanup once, after the outermost active run finishes.
`removeAllSystems` also removes unresolved references but preserves phases and pipelines. System entities cannot be cloned.
Deleting a dependency removes its ordering constraint. Deleting a phase leaves its systems invalid until they receive valid phase membership.
Registration and removal participate in storage observation, including reads of `systemCount`.

## Synchronization points

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

