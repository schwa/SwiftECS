# World-owned mutation scope (#24)

Status: Implemented.

## Problem

World, typed rows, component references, and relationship methods separately coordinate writes and invalidation. World also couples batch state to simulation updates.

Correctness depends on each path publishing events after its writes and invalidating storage afterward. Tests reach into the observer registry rather than testing all subscriber behavior through World.

## Chosen interface

World owns an internal mutation coordinator. Its main sequencing operations are:

```swift
mutations.perform {
    // Complete a storage-only mutation.
}

mutations.perform({
    // Complete all component writes.
}, events: {
    // Deliver component events synchronously.
})

try mutations.batch {
    // Run a group of operations, including nested batches.
}
```

The coordinator owns component-event dispatch, observation access, and batch state. The storage engine still owns entity locations and archetype transitions.

No public API changes. Invalid operations and no-ops return before entering a mutation scope. Mutation bodies do not throw. Validation occurs first.

Creation, cloning, and deletion retain their storage-only notification behavior. They do not synthesize component events.

The write scope invalidates after event delivery. Event handlers can reenter World. Nested callbacks remain synchronous and retain current ordering. A whole-row setter finishes all writes before its first event.

Batches coalesce storage invalidation and flush on every exit, including thrown errors. Simulation time remains separately observable. Component events remain unbatched.

## Dependency strategy

All dependencies are in-process. The coordinator owns a Swift Observation registrar and the subscriber table. The separate observer registry is removed. Typed writers use nonescaping, inlinable closures to preserve specialization.

The coordinator does not add actor isolation, asynchronous delivery, or a public transaction API. It remains within World single-owner access rules.

## Testing strategy

Replace direct ObserverRegistry tests with World.observe tests for subscriber removal, repeated removal, registration after removal, self-removal, and type identity.

Keep public storage observation and relationship tests. Add boundary cases for event-state visibility, all write entry points, reentrant mutation, nested/error batch exits, and no-op writes.

Compiler probes remain separate from behavioral tests. Run Debug/Release suites and the typed-query Release benchmark against a measured baseline.

## Migration

Storage mutations enter the coordinator after validation. Typed references no longer coordinate dispatch and invalidation themselves. Relationship writes, creation, cloning, and deletion use the same storage-only scope.

World.update and recursive deletion use the same batch operation. Neither owns batch counters directly. Read APIs register storage dependencies through the coordinator.
