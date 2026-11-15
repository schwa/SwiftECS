# Observation

Observe component events and drive SwiftUI from a world.

## Observe component events

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
Creation, cloning, and entity deletion invalidate storage but do not synthesize component events.
Whole-row writes finish before the first component event. Storage invalidation follows event delivery, and nested batches flush even when execution throws.

## Use SwiftUI observation

A plain `World` does not take part in Swift Observation. Create an ``ObservableWorld`` and use its `world` to drive views.

```swift
import SwiftUI

@MainActor
struct EntityCountView: View {
    @State private var observable = ObservableWorld()

    var body: some View {
        let world = observable.world
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

`World` is not thread-safe. Keep an observable world on the main actor. A plain world can live on any one actor or task. Internal mutations of reference-type components require an ECS write to notify observation.

