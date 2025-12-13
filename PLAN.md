# ECS Plan

## Completed Features

- [x] Archetype-based storage
- [x] Entity handles with component access
- [x] Query predicates (has, and, or, not)
- [x] System dependencies with topological sort
- [x] Component observers
- [x] Registered query caching
- [x] `@Observable` World with `simulationTime`

---

# ECS Performance Plan

## Current Performance (100K entities, 60 frames)

| Method | Time | Per Frame | Notes |
|--------|------|-----------|-------|
| `EntityRef` (dictionary columns) | ~25,000ms | ~420ms | Current fast path |
| `Entity` subscript via world | ~50,000ms | ~830ms | Slow path |
| query + get + set | ~45,000ms | ~750ms | Slowest |

## Target Performance

The original `forEach` with direct column access achieved:
- ~1,500ms total (~25ms per frame)

This is **~20x faster** than current best.

## Why Dictionary Lookup is Slow

`EntityRef` currently uses `[ComponentType: AnyColumn]` dictionary:
```swift
public subscript<C: Component>(type: C.Type) -> C {
    get {
        let col = columns[ComponentType(type)] as! Column<C>  // Dictionary lookup + cast
        return col.data[index]
    }
}
```

Each component access requires:
1. Create `ComponentType` from metatype
2. Dictionary hash + lookup
3. Type cast `AnyColumn` to `Column<C>`

## Proposed Solutions

### Option 1: Explicit Typed Overloads (Proven Fast)

Create `EntityRef1<T1>`, `EntityRef2<T1,T2>`, `EntityRef3<T1,T2,T3>` etc. with direct typed column storage:

```swift
public struct EntityRef2<T1: Component, T2: Component> {
    public let entityID: EntityID
    private let col1: Column<T1>  // Direct reference, no lookup
    private let col2: Column<T2>
    private let index: Int
    
    public subscript(type: T1.Type) -> T1 {
        get { col1.data[index] }           // Direct array access
        nonmutating set { col1.data[index] = newValue }
    }
    // ...
}
```

**Pros:** 
- Proven ~25ms/frame performance
- Type safe at compile time
- No runtime overhead

**Cons:**
- Need multiple overloads (EntityRef1, EntityRef2, EntityRef3, EntityRef4, EntityRef5...)
- Boilerplate code

### Option 2: Parameter Packs (Compiler Crashes)

Tried generic `EntityRef<each T: Component>` but Swift compiler crashes:
```
signal 11 in emitPackExpansionIntoPack
```

This is a Swift compiler bug. May work in future Swift versions.

### Option 3: Cached Column Array in EntityRef

Store columns in array with known indices:
```swift
public struct EntityRef {
    let entityID: EntityID
    let columns: [AnyColumn]  // Array, not dictionary
    let index: Int
    
    // Component type -> array index mapping done once at iterator creation
}
```

Would need type-index mapping passed through, but avoids dictionary lookup per access.

### Option 4: Code Generation / Macros

Use Swift macros to generate EntityRef variants:
```swift
@GenerateEntityRef(maxComponents: 8)
// Generates EntityRef1, EntityRef2, ..., EntityRef8
```

## Recommended Path

1. **Short term:** Add explicit `EntityRef2`, `EntityRef3` overloads for common cases (2-4 components)
2. **Medium term:** Investigate macro-based generation
3. **Long term:** Wait for Swift parameter pack fixes, revisit generic approach

## Other Performance Notes

### Archetype Creation

Adding components one-at-a-time creates intermediate archetypes:
```swift
entity.set(A())  // Archetype [A]
entity.set(B())  // Archetype [A,B], [A] now empty
entity.set(C())  // Archetype [A,B,C], [A,B] now empty
```

**Mitigation:** Use `createEntity(A(), B(), C())` to go directly to final archetype.

**Future:** Could add empty archetype garbage collection.

### Query Registration

Registering queries caches matching archetypes:
```swift
world.register(query)  // Cache which archetypes match
```

This avoids re-evaluating predicates on every iteration. Cache invalidates when new archetypes are created.

### EntityRef Bypasses Observers

`EntityRef` writes directly to archetype columns for performance, bypassing the `World` notification system:

```swift
// This triggers .changed observer
entity.set(Position(x: 10, y: 20))

// This does NOT trigger observers (fast path)
for ref in world.entities(query, Position.self) {
    ref[Position.self] = Position(x: 10, y: 20)  // No notification
}
```

This is intentional - observer overhead would negate the performance benefit. Users needing change tracking should use `entity.set()` or implement their own dirty-flagging within systems.

## Future Considerations

### Observable Properties

Currently only `simulationTime` is observable. Could consider adding:
- `isPaused: Bool` - for pause/resume functionality
- `systemCount: Int` - for debug UI (low frequency changes)

High-frequency internal state (entities, archetypes) should remain `@ObservationIgnored`.
