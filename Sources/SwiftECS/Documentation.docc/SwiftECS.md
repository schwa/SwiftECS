# ``SwiftECS``

A type-safe, archetype-based Entity Component System for Swift 6, with strict concurrency and parallel systems.

## Overview

A ``World`` stores entities. Each ``Entity`` holds a set of ``Component`` values. Entities with the same component types share an archetype, so queries iterate dense columns. ``System`` values run over queries in phases and pipelines, either serially or in parallel when their inputs allow it.

## Topics

### Essentials

- <doc:GettingStarted>
- ``World``
- ``Entity``
- ``EntityID``
- ``Component``

### Queries

- ``Query``
- ``QuerySequence``
- ``TypedQuerySequence``
- ``ComponentRef``
- ``TypedEntityRef``

### Systems and Scheduling

- <doc:Systems>
- ``System``
- ``SystemContext``
- ``Read``
- ``Write``
- ``Commands``
- ``Phase``
- ``Pipeline``

### Parallel Execution

- <doc:ParallelSystems>
- ``ConcurrentComponent``
- ``ParallelSystemInput``

### Entity Relationships

- <doc:Relationships>
- ``Relationship``
- ``ChildOf``

### Observing Changes

- <doc:Observation>
- ``ComponentEvent``
- ``ComponentChange``
- ``RelationshipEvent``
- ``ObservationToken``

### Measurements

- <doc:Performance>
