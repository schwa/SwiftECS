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

## Installation

```swift
.package(url: "https://github.com/schwa/SwiftECS", from: "0.1.0")
```

## Usage

Components are plain structs. Entities hold components. Systems query entities and update them each frame.

```swift
import SwiftECS

// A component is a plain struct.
struct Position: Component { var x, y: Double }
struct Velocity: Component { var x, y: Double }

// Make a world and add one entity with two components.
let world = World()
world.createEntity(Position(x: 0, y: 0), Velocity(x: 1, y: 0))

// Add a system that moves each entity that has both components.
try world.addSystem(System("movement")
    .query(Write<Position>(), Read<Velocity>())
    .each { context, position, velocity in
        position.value.x += velocity.x * context.deltaTime
    })

// Run all systems for one frame.
try world.update(deltaTime: 1.0 / 60)
```

## Performance

The benchmark runs one movement system over 100,000 entities. Each cell is the time for one `world.update` in milliseconds. Lower is better.

- **Rows:** the extra work that the system does for each entity, in addition to the movement. This work is a loop of `sin` and `cos` that stands in for real logic, such as steering or collision. One loop iteration takes about 10 ns.
- **Columns:** "Serial" runs the system on one thread. The other columns run it as a parallel system with that many worker tasks.

| Extra work per entity | Serial | 4 workers | 6 workers | 12 workers | 18 workers |
|---|---:|---:|---:|---:|---:|
| None | 8.6 | 9.7 | 5.8 | 5.4 | 4.2 |
| ~0.1 µs (10 iterations) | 19.4 | 11.1 | 7.5 | 6.1 | 4.9 |
| ~0.5 µs (50 iterations) | 59.4 | 19.2 | 13.1 | 9.8 | 7.7 |
| ~2 µs (200 iterations) | 214.3 | 58.5 | 42.0 | 22.9 | 19.8 |

Release build on an Apple M5 Max (6 performance cores and 12 efficiency cores).

Parallel systems help when each entity does real work. For very light work, serial is about as fast. Run `just benchmark` to measure on your machine.

## Documentation

[SwiftECS documentation](https://schwa.github.io/SwiftECS/documentation/swiftecs/)

## License

MIT, see [LICENSE](LICENSE).
