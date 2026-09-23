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

/// Entity location within archetype storage.
struct EntityLocation {
    let signature: ArchetypeSignature
    var index: Int
}

/// Type-erased column storage.
protocol AnyColumn: AnyObject {
    func swapRemove(at index: Int)
    func makeEmptyColumn() -> AnyColumn
    func copyValue(at sourceIndex: Int, to target: AnyColumn, at targetIndex: Int)
    func getValue(at index: Int) -> (any Component)?
}

/// Typed column storage for one component type.
@usableFromInline
final class Column<T: Component>: AnyColumn {
    @usableFromInline var data: [T] = []

    @inlinable
    func setValue(_ value: T, at index: Int) {
        data[index] = value
    }

    func swapRemove(at index: Int) {
        if index < data.count - 1 {
            data[index] = data[data.count - 1]
        }
        data.removeLast()
    }

    func makeEmptyColumn() -> AnyColumn {
        Column<T>()
    }

    func copyValue(at sourceIndex: Int, to target: AnyColumn, at targetIndex: Int) {
        guard let targetColumn = target as? Column<T> else { return }
        let value = data[sourceIndex]
        while targetColumn.data.count <= targetIndex {
            targetColumn.data.append(value)
        }
        targetColumn.data[targetIndex] = value
    }

    func getValue(at index: Int) -> (any Component)? {
        guard index < data.count else { return nil }
        return data[index]
    }
}

/// Storage for entities with the same component signature.
@usableFromInline
final class Archetype {
    let signature: ArchetypeSignature
    @usableFromInline private(set) var entities: [EntityID] = []
    internal var columns: [ComponentType: AnyColumn] = [:]

    init(signature: ArchetypeSignature) {
        self.signature = signature
    }

    func addEntity(_ entityID: EntityID) -> Int {
        let index = entities.count
        entities.append(entityID)
        return index
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

        while col.data.count <= index {
            col.data.append(value)
        }
        if col.data.count == index {
            col.data.append(value)
        } else {
            col.data[index] = value
        }
    }

    func getComponent<T: Component>(_ type: T.Type, at index: Int) -> T? {
        guard let col = columns[ComponentType(type)] as? Column<T>,
              index < col.data.count else { return nil }
        return col.data[index]
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
