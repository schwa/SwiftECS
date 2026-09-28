# SwiftECS

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

These are sequential synchronization points, not parallel system execution. Captured world access remains outside the declared-access contract, except for explicit nested runs.

The opt-in `SynchronizationPerformanceTests` compares `.automatic` with `.afterEachSystem` using identical commands and final-state checks:

```sh
ECS_RUN_SYNC_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter SynchronizationPerformanceTests
```

The initial 32-producer measurement reduced merges from 32 to 1 for 4,096 commands per frame.
Median frame time was 4.06 ms automatically versus 3.99 ms per-system. Fewer merges did not improve runtime in this workload.

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
