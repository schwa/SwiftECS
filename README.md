# SwiftECS

A type-safe, archetype-based Entity Component System for Swift 6, with strict concurrency and parallel systems.

![Midnight Survivors, the SwiftECS demo game](Images/midnight-survivors.png)

## Features

- Archetype storage with cached, typed queries built on parameter packs
- Composable query predicates (`&&`, `||`, `!`), including relationship-based queries
- Systems with phases, pipelines, dependencies, and deferred commands
- Opt-in parallel systems, checked for data races at compile time
- Entity relationships with hierarchies, cycle checks, and recursive deletion
- Component, destroy, and relationship observers that report old and new values
- SwiftUI Observation support, with batched notifications
- Stable typed component references for hot loops

## Requirements

The package requires Swift 6.2 or later. Declared Apple deployment targets are macOS, iOS, and visionOS 26 or later.

## Usage

Components are plain structs. Entities hold components. Systems query entities and update them each frame.

```swift
import SwiftECS

struct Position: Component { var x, y: Double }
struct Velocity: Component { var x, y: Double }

let world = World()
world.createEntity(Position(x: 0, y: 0), Velocity(x: 1, y: 0))

try world.addSystem(System("movement")
    .query(Write<Position>(), Read<Velocity>())
    .each { context, position, velocity in
        position.value.x += velocity.x * context.deltaTime
    })
try world.update(deltaTime: 1.0 / 60)
```

See the DocC catalog in `Sources/SwiftECS/Documentation.docc` for queries, systems, parallel execution, relationships, and observation.

## License

MIT, see [LICENSE](LICENSE).
