# ECS

## Protocols

### `Component`

Marker protocol for component data.

```swift
public protocol Component
```

<sub>Defined in `Sources/ECS/Component.swift`</sub>

---

### `System`

Logic that operates on entities.

```swift
public protocol System
```

<sub>Defined in `Sources/ECS/System.swift`</sub>

#### Methods

##### `cleanup`

Called when the system is removed from the world.

```swift
func cleanup(world: World)
```

##### `cleanup`

Default empty implementation.

```swift
func cleanup(world: World)
```

##### `initialize`

Called when the system is added to the world.

```swift
func initialize(world: World)
```

##### `initialize`

Default empty implementation.

```swift
func initialize(world: World)
```

##### `update`

Called each frame to update entity state.

```swift
func update(world: World, deltaTime: Double)
```

---

## Classes

### `World`

Container for entities, components, and systems.

```swift
public final class World
```

<sub>Defined in `Sources/ECS/World.swift`</sub>

#### Properties

##### `entities`

All entities.

```swift
public var entities: [Entity]
```

##### `entityCount`

Number of entities.

```swift
public var entityCount: Int
```

#### Initializers

##### `init`

Create an empty world.

```swift
public init()
```

#### Methods

##### `addSystem`

Add a system.

```swift
public func addSystem(_ system: System)
```

##### `createEntity`

Create an entity with no components.

```swift
@discardableResult public func createEntity() -> Entity
```

##### `createEntity`

Create an entity with components.

```swift
@discardableResult public func createEntity<each T: Component>(_ components: repeat each T) -> Entity
```

##### `entities`

Get entities with all specified components.

```swift
public func entities<each T: Component>(with componentTypes: repeat (each T).Type) -> [Entity]
```

##### `entityExists`

Check if an entity exists.

```swift
public func entityExists(_ id: EntityID) -> Bool
```

##### `forEach`

Iterate entities with one component.

```swift

```

##### `forEach`

Iterate entities with two components.

```swift
public func forEach<T1: Component, T2: Component>( _ type1: T1.Type, _ type2: T2.Type, body: (Entity, T1, T2) -> Void )
```

##### `forEachMutable`

Iterate entities with one component (mutable).

```swift
public func forEachMutable<T: Component>(_ type: T.Type, body: (Entity, inout T) -> Void)
```

##### `forEachMutable`

Iterate entities with two components (mutable).

```swift
public func forEachMutable<T1: Component, T2: Component>( _ type1: T1.Type, _ type2: T2.Type, body: (Entity, inout T1, inout T2) -> Void )
```

##### `forEachMutable`

Iterate entities with three components (mutable).

```swift
public func forEachMutable<T1: Component, T2: Component, T3: Component>( _ type1: T1.Type, _ type2: T2.Type, _ type3: T3.Type, body: (Entity, inout T1, inout T2, inout T3) -> Void )
```

##### `removeAllSystems`

Remove all systems.

```swift
public func removeAllSystems()
```

##### `update`

Update all systems.

```swift
public func update(deltaTime: Double)
```

#### Subscripts

##### `subscript`

Get an entity handle.

```swift
public subscript(id: EntityID) -> Entity?
```

---

## Structures

### `Composite`

A variadic container for bundling multiple values using parameter packs.

```swift
public struct Composite
```

**Conforms to:** `Equatable` where repeat each T: Equatable, `Hashable` where repeat each T: Hashable

<sub>Defined in `Sources/ECS/Composite.swift`</sub>

#### Initializers

##### `init`

Create a composite from variadic values.

```swift
public init(_ children: repeat each T)
```

#### Methods

##### `==`

Returns true if all corresponding elements are equal.

```swift
public static func == (lhs: Self, rhs: Self) -> Bool
```

##### `hash`

Hashes all elements into the hasher.

```swift
public func hash(into hasher: inout Hasher)
```

---

### `Entity`

Handle for accessing an entity's components.

```swift
public struct Entity
```

<sub>Defined in `Sources/ECS/Entity.swift`</sub>

#### Properties

##### `exists`

Check if entity still exists.

```swift
public var exists: Bool
```

##### `id`

The unique identifier for this entity.

```swift
public let id: EntityID
```

#### Methods

##### `add`

Add or update a component.

```swift
@discardableResult public func add<T: Component>(_ component: T) -> Entity
```

##### `destroy`

Remove this entity from the world.

```swift
@discardableResult public func destroy() -> Bool
```

##### `has`

Check if entity has a component.

```swift
public func has<T: Component>(_ type: T.Type) -> Bool
```

##### `remove`

Remove a component.

```swift
@discardableResult public func remove<T: Component>(_ type: T.Type) -> T?
```

#### Subscripts

##### `subscript`

Get a component.

```swift
public subscript<T: Component>(_ type: T.Type) -> T?
```

---

### `EntityID`

Unique entity identifier.

```swift
public struct EntityID: Hashable, Equatable, Sendable
```

**Conforms to:** `Hashable`, `Equatable`, `Sendable`

<sub>Defined in `Sources/ECS/Entity.swift`</sub>

#### Properties

##### `value`

The underlying integer value.

```swift
public let value: UInt64
```

#### Initializers

##### `init`

Create an entity ID from a raw value.

```swift
public init(_ value: UInt64)
```

---

