# ECS

A high-performance Entity Component System for Swift using archetype-based storage.

## Overview

ECS is an architectural pattern that separates data (Components) from behavior (Systems). Entities are unique IDs that group components together. This implementation uses archetype storage for cache-friendly iteration.

## Requirements

- Swift 6.2+
- macOS 14+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/ECS", from: "1.0.0")
]
```

## Quick Start

```swift
import ECS

// Define components (pure data)
struct Position: Component {
    var x: Double
    var y: Double
}

struct Velocity: Component {
    var dx: Double
    var dy: Double
}

// Create world and entities
let world = World()

let player = world.createEntity(
    Position(x: 0, y: 0),
    Velocity(dx: 1, dy: 0)
)

// Work with entity handles
player.add(Health(current: 100))
player.has(Position.self)        // true
player.component(Position.self)  // Position?

// Define a system
struct MovementSystem: System {
    func update(world: World, deltaTime: Double) {
        world.forEachMutable(Position.self, Velocity.self) { entity, pos, vel in
            pos.x += vel.dx * deltaTime
            pos.y += vel.dy * deltaTime
        }
    }
}

// Run
world.addSystem(MovementSystem())
world.update(deltaTime: 1.0 / 60.0)
```

## Architecture

### Archetype Storage

Entities are grouped by their component signature (the set of component types they have). Each group is called an **archetype**. Components within an archetype are stored in parallel arrays:

```
Archetype {Position, Velocity}
├── entities: [E1, E2, E3]
├── Position: [P1, P2, P3]  ← contiguous in memory
└── Velocity: [V1, V2, V3]  ← contiguous in memory

Archetype {Position}
├── entities: [E4, E5]
└── Position: [P4, P5]
```

**Benefits:**
- Cache-friendly iteration (sequential memory access)
- Fast queries (scan archetypes, not individual entities)
- No wasted memory for missing components

**Trade-offs:**
- Adding/removing components moves entity between archetypes
- Best for stable component configurations

## API Reference

### Entity Management

```swift
// Create entities
let e1 = world.createEntity()                              // Empty entity
let e2 = world.createEntity(Position(x: 0, y: 0))          // With components
let e3 = world.createEntity(pos, vel, health)              // Variadic

// Access by ID
world[entityID]             // Entity?

// Query
world.entities              // [Entity] - all entities
world.entities(with: Position.self)                        // With 1 component
world.entities(with: Position.self, Velocity.self)         // With multiple
world.entityCount           // Int
```

### Entity Handle

```swift
entity.id                   // EntityID
entity.exists               // Bool

// Components
entity.add(Position(...))   // Add/update, returns self for chaining
entity.component(Position.self)  // T?
entity.has(Position.self)        // Bool
entity.remove(Position.self)     // T?

// Lifecycle
entity.destroy()            // Bool
```

### Iteration

The primary way to process entities. Iterates contiguous memory for best performance.

```swift
// Read-only
world.forEach(Position.self) { entity, pos in ... }
world.forEach(Position.self, Velocity.self) { entity, pos, vel in ... }

// Mutable
world.forEachMutable(Position.self) { entity, pos in
    pos.x += 1
}
world.forEachMutable(Position.self, Velocity.self) { entity, pos, vel in
    pos.x += vel.dx
}
world.forEachMutable(A.self, B.self, C.self) { entity, a, b, c in ... }
```

### Systems

```swift
struct MySystem: System {
    // Required
    func update(world: World, deltaTime: Double) { ... }
    
    // Optional (default empty implementations)
    func initialize(world: World) { ... }  // Called on addSystem
    func cleanup(world: World) { ... }     // Called on removeAllSystems
}

// Usage
world.addSystem(MySystem())
world.update(deltaTime: dt)
world.removeAllSystems()
```

## Performance

Benchmarks on Apple Silicon (Release build):

| Operation | Time |
|-----------|------|
| Create 100K entities | ~15ms |
| Create 100K entities + 3 components | ~200ms |
| forEach (100K entities, 2 components) | ~2ms |
| 60 frame physics (100K entities) | ~1200ms (~20ms/frame) |

### Tips

1. **Use `createEntity()` with components** - Avoids archetype transitions
2. **Use `forEach`/`forEachMutable`** - Fastest iteration, cache-friendly
3. **Minimize runtime component changes** - Adding/removing components has overhead
4. **Use Entity handles** - More ergonomic than working with EntityIDs directly

## Documentation

API documentation is in `docs/ECS.md`. Regenerate with:

```bash
headerdoc2md
```

## License

MIT
