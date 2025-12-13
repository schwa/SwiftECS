# AGENTS.md

This is a Swift ECS (Entity Component System) library using archetype-based storage.

## Key Files

- `Sources/ECS/World.swift` - Main container for entities, components, and systems
- `Sources/ECS/Entity.swift` - Entity handle with component access
- `Sources/ECS/Query.swift` - Query predicates and iteration
- `Sources/ECS/System.swift` - System protocol and execution
- `Sources/ECS/Archetype.swift` - Archetype storage implementation
- `Sources/ECS/Observer.swift` - Component change observation

## Architecture

- **Archetype storage**: Entities grouped by component signature for cache-friendly iteration
- **World is @Observable**: Only `simulationTime` triggers observation (internal state is ignored)
- **Query-based iteration**: `forEach`/`forEachMutable` for efficient component access

## Conventions

- Components are value types conforming to `Component` protocol
- Systems implement `System` protocol with `update(world:deltaTime:)`
- Use `createEntity(components...)` to avoid archetype transitions
- Use `forEachMutable` for performance-critical iteration
