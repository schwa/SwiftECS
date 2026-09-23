# ECS

## Usage

### Components and entities

```swift
import ECS

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

for reference in world.references(active, Position.self, Velocity.self) {
    var position = reference[Position.self]
    position.x += reference[Velocity.self].x * deltaTime
    reference[Position.self] = position
}
```

`entities(matching:)` lazily returns handles. `references` is the older untyped fast-reference path. `snapshot` returns an array of handles with fixed membership, not frozen component values.

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

```swift
struct MovementSystem: System {
    func update(world: World, deltaTime: Double) {
        for row in world.query(Position.self, Velocity.self) {
            var (position, velocity) = row.values
            position.x += velocity.x * deltaTime
            position.y += velocity.y * deltaTime
            row.set(position, velocity)
        }
    }
}

struct RegenerationSystem: System {
    static let query = Query(with: Health.self)

    func initialize(world: World) {
        world.register(Self.query)
    }

    func update(world: World, deltaTime: Double) {
        for row in world.query(Health.self, matching: Self.query) {
            row.set(Health(current: min(100, row.values.current + 1)))
        }
    }

    func cleanup(world: World) {
        world.unregister(Self.query)
    }
}

try world.addSystem(MovementSystem(), id: "movement")
try world.addSystem(RegenerationSystem(), id: "regeneration", dependencies: ["movement"])
try world.update(deltaTime: 1.0 / 60)

let elapsed = world.simulationTime
let order = world.systemExecutionOrder
let systemCount = world.systemCount
world.removeAllSystems()

try world.addSystem(MovementSystem())      // Uses the type name as its ID
let movementID = SystemID.of(MovementSystem.self)
```

System lifecycle hooks have empty defaults. Registration always throws on duplicate IDs. `update` advances simulation time before it runs systems and throws for missing dependencies or cycles.

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
