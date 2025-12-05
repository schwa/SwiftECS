# AGENT.md

Guidelines for AI agents working on this codebase.

## Project Overview

Swift 6.2 Package implementing an Entity Component System (ECS) with archetype-based storage.

## Files

```
Sources/ECS/
├── World.swift      # Main container, public API
├── Entity.swift     # Entity handle and EntityID
├── Component.swift  # Component protocol
├── System.swift     # System protocol with lifecycle hooks
├── Archetype.swift  # Internal storage (archetypes, columns)
├── Composite.swift  # Parameter pack helper type
└── ECS.swift        # Module marker

Tests/ECSTests/
├── ECSTests.swift       # Unit tests
├── StressTests.swift    # Performance tests
└── TestComponents.swift # Test fixtures

docs/
└── ECS.md           # Auto-generated API documentation
```

## Architecture

**Archetype storage**: Entities with same component types stored together in columnar arrays.

```
World
├── archetypes: [Signature: Archetype]
├── entityLocations: [EntityID: (Signature, Index)]
└── systems: [System]

Archetype
├── signature: Set<ObjectIdentifier>
├── entities: [EntityID]
└── columns: [ObjectIdentifier: Column<T>]
```

**Key insight**: `forEach`/`forEachMutable` iterate contiguous memory. Adding/removing components moves entities between archetypes.

## Public API

- `Entity` - Handle for accessing entity's components (primary interface)
- `EntityID` - Unique entity identifier
- `Component` - Protocol for component data
- `System` - Protocol for systems with `update`, `initialize`, `cleanup`
- `World` - Container with entity/component/system management
- `Composite` - Parameter pack helper for bundling values

## Internal Types

- `ArchetypeSignature` - Set of component types
- `Archetype` - Storage for entities with same signature
- `Column<T>` - Typed component array
- `EntityLocation` - Entity's archetype + index

## Commands

```bash
swift build
swift test
swift test -c release
swift test --filter Stress
periphery scan
headerdoc2md                # Regenerate docs/ECS.md from source
```

## API Style

The API is Entity-focused:

```swift
// Create entities
let entity = world.createEntity(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1))

// Work with Entity handles
entity.add(Health(current: 100))
entity.has(Position.self)
entity.component(Position.self)
entity.remove(Velocity.self)
entity.destroy()

// Query entities
world.entities                              // All entities
world.entities(with: Position.self)         // With specific components
world[entityID]                             // Subscript access

// Iteration
world.forEach(Position.self) { entity, pos in ... }
world.forEachMutable(Position.self, Velocity.self) { entity, pos, vel in ... }
```

## Parameter Packs

Uses Swift parameter packs for variadic APIs:
- `createEntity(_ components: repeat each T)`
- `entities(with types: repeat (each T).Type)`

Note: `forEach` with `Composite` is commented out due to Swift compiler crash (SILGen bug). See World.swift.

## Common Tasks

### Add forEach for 4+ components

Add to `World.swift`:
```swift
public func forEachMutable<T1, T2, T3, T4: Component>(
    _ type1: T1.Type, _ type2: T2.Type, _ type3: T3.Type, _ type4: T4.Type,
    body: (Entity, inout T1, inout T2, inout T3, inout T4) -> Void
) { ... }
```

### Update documentation

Run `headerdoc2md` to regenerate `docs/ECS.md` from source doc comments.

## Style

- Entity-focused public API (use Entity handles, not EntityIDs directly)
- Internal types stay internal
- Minimal public API surface
- Value types preferred
- No external dependencies (except swift-docc-plugin for docs)
