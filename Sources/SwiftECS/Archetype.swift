/// Set of component types identifying an archetype.
struct ArchetypeSignature: Hashable {
    let types: Set<ComponentType>

    init(_ types: Set<ComponentType> = []) {
        self.types = types
    }

    func adding(_ type: ComponentType) -> Self {
        var newTypes = types
        newTypes.insert(type)
        return Self(newTypes)
    }

    func removing(_ type: ComponentType) -> Self {
        var newTypes = types
        newTypes.remove(type)
        return Self(newTypes)
    }

    func contains(_ type: ComponentType) -> Bool {
        types.contains(type)
    }

    func isSuperset(of other: Set<ComponentType>) -> Bool {
        types.isSuperset(of: other)
    }
}

// Holds the archetype itself: looking it up by signature hashes and compares a Set of every component type, which
// dominated per-entity access for entities with many components.
/// Entity location within archetype storage.
struct EntityLocation {
    let archetype: Archetype
    var index: Int

    var signature: ArchetypeSignature {
        archetype.signature
    }

    var archetypeSerial: UInt64 {
        archetype.serial
    }
}

/// Type-erased column storage.
@usableFromInline
protocol AnyColumn: AnyObject {
    func swapRemove(at index: Int)
    func makeEmptyColumn() -> AnyColumn
    func copyValue(at sourceIndex: Int, to target: AnyColumn, at targetIndex: Int)
    func getValue(at index: Int) -> (any Component)?
    var count: Int { get }
}

/// Typed column storage for one component type.
@usableFromInline
final class Column<T: Component>: AnyColumn {
    // Made in the inlinable init, so it is specialized for T wherever the column is created. swapRemove is called
    // through AnyColumn, where the generic body would look up T's metadata on every call.
    @usableFromInline let swapRemoveImplementation: (Column<T>, Int) -> Void

    @inlinable
    init() {
        swapRemoveImplementation = { column, index in
            column.withLock {
                let last = column.storage.count - 1
                if index < last {
                    column.storage[index] = column.storage[last]
                }
                column.storage.removeLast()
            }
        }
    }

    @usableFromInline
    var count: Int {
        withLock { storage.count }
    }

    // ABI-visible for generic specialization; storage access goes through withLock.
    @usableFromInline let lock = ScopedLock()
    @usableFromInline var storage: ContiguousArray<T> = []

    @inlinable
    @inline(__always)
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        try lock.withLock(body)
    }

    @inlinable
    @inline(__always)
    func value(at index: Int) -> T {
        withLock { storage[index] }
    }

    @inlinable
    @inline(__always)
    func setValue(_ value: T, at index: Int) {
        withLock { storage[index] = value }
    }

    // Without the lock. Only for serial World access after checkAccessible(): parallel jobs run only while the
    // World is suspended, so no other thread can touch the column then (#49).
    @inlinable
    @inline(__always)
    func serialValue(at index: Int) -> T {
        storage[index]
    }

    @inlinable
    @inline(__always)
    func setSerialValue(_ value: T, at index: Int) {
        storage[index] = value
    }

    func snapshot() -> ContiguousArray<T> {
        withLock { storage }
    }

    func apply(_ values: ContiguousArray<T>, indices: [Int]?, changed: [Bool]) {
        withLock {
            for index in values.indices where changed[index] {
                storage[indices?[index] ?? index] = values[index]
            }
        }
    }

    func insert(_ value: T, at index: Int) {
        withLock {
            while storage.count <= index {
                storage.append(value)
            }
            storage[index] = value
        }
    }

    @usableFromInline
    func swapRemove(at index: Int) {
        swapRemoveImplementation(self, index)
    }

    @usableFromInline
    func makeEmptyColumn() -> AnyColumn {
        Column<T>()
    }

    @usableFromInline
    func copyValue(at sourceIndex: Int, to target: AnyColumn, at targetIndex: Int) {
        guard let targetColumn = target as? Column<T> else { return }
        targetColumn.insert(value(at: sourceIndex), at: targetIndex)
    }

    @usableFromInline
    func getValue(at index: Int) -> (any Component)? {
        valueIfPresent(at: index)
    }

    func valueIfPresent(at index: Int) -> T? {
        withLock {
            guard index < storage.count else { return nil }
            return storage[index]
        }
    }
}

// Every storage access is locked; only eligible component columns can cross tasks.
extension Column: @unchecked Sendable where T: ConcurrentComponent {}

/// Storage for entities with the same component signature.
@usableFromInline
final class Archetype {
    let signature: ArchetypeSignature
    // Never reused in a World, unlike the object's address after the archetype is reclaimed.
    let serial: UInt64
    @usableFromInline private(set) var entities: [EntityID] = []
    @usableFromInline internal var columns: [ComponentType: AnyColumn] = [:]

    init(signature: ArchetypeSignature, serial: UInt64) {
        self.signature = signature
        self.serial = serial
    }

    func addEntity(_ entityID: EntityID) -> Int {
        let index = entities.count
        entities.append(entityID)
        return index
    }

    // For serial World access only (no column lock), specialized at the caller; see World.createEntity(id:types:_:).
    @inlinable
    func setSerialComponent<T: Component>(_ value: T, at index: Int) {
        let typeID = ComponentType(T.self)
        let column: Column<T>
        if let existing = columns[typeID] {
            // swiftlint:disable:next force_cast
            column = existing as! Column<T>
        } else {
            column = Column<T>()
            columns[typeID] = column
        }
        if column.storage.count == index {
            column.storage.append(value)
        } else {
            while column.storage.count <= index {
                column.storage.append(value)
            }
            column.storage[index] = value
        }
    }

    func setComponent<T: Component>(_ value: T, at index: Int) {
        let typeID = ComponentType(T.self)
        let col: Column<T>
        if let existing = columns[typeID] as? Column<T> {
            col = existing
        } else {
            col = Column<T>()
            columns[typeID] = col
        }

        col.insert(value, at: index)
    }

    func getComponent<T: Component>(_ type: T.Type, at index: Int) -> T? {
        guard let col = columns[ComponentType(type)] as? Column<T> else { return nil }
        return col.valueIfPresent(at: index)
    }

    func removeEntity(at index: Int) -> EntityID? {
        guard index < entities.count else { return nil }

        let lastIndex = entities.count - 1
        let movedEntity: EntityID? = (index < lastIndex) ? entities[lastIndex] : nil

        for (_, column) in columns {
            column.swapRemove(at: index)
        }

        if index < lastIndex {
            entities[index] = entities[lastIndex]
        }
        entities.removeLast()

        return movedEntity
    }

    func column<T: Component>(for type: T.Type) -> Column<T>? {
        columns[ComponentType(type)] as? Column<T>
    }

    func allComponents(at index: Int) -> [any Component] {
        columns.values.compactMap { $0.getValue(at: index) }
    }

    func copyComponents(at index: Int, to target: Archetype, targetIndex: Int, excludeType: ComponentType? = nil) {
        for (typeID, column) in columns {
            if typeID == excludeType { continue }

            let targetColumn: AnyColumn
            if let existing = target.columns[typeID] {
                targetColumn = existing
            } else {
                targetColumn = column.makeEmptyColumn()
                target.columns[typeID] = targetColumn
            }
            column.copyValue(at: index, to: targetColumn, at: targetIndex)
        }
    }
}
