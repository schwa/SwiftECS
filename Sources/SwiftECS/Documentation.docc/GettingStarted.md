# Getting Started

Define components, create entities, and query them.

## Components and entities

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

## Read and change components

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

## Build queries

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

## Iterate and update

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

## Cache repeated queries

Registration caches matching archetypes, not component values or relationship results.

```swift
world.register(active)
let registered = world.isRegistered(active)

for row in world.query(Position.self, Velocity.self, matching: active) {
    let (position, velocity) = row.values
}

world.unregister(active)
```


## Inspect storage

```swift
let types = owner.componentTypes
let components = owner.allComponents
let typeName = ComponentType(Health.self).name

let stats = world.stats
let summary = world.dumpString()
let detail = world.dumpDetailed()
```
