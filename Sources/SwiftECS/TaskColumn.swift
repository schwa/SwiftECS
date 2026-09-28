@usableFromInline
internal protocol AnyTaskColumn: AnyObject {
    func finish() -> ParallelValueUpdate?
}

@usableFromInline
internal final class TaskColumn<Value: Component>: AnyTaskColumn {
    @usableFromInline let valuesCell: OwnerCell<ContiguousArray<Value>>
    @usableFromInline let changedCell = OwnerCell<[Bool]?>(nil)
    @inlinable var values: ContiguousArray<Value> {
        _read { yield valuesCell.pointer.pointee }
        _modify { yield &valuesCell.pointer.pointee }
    }
    private let makeUpdate: (ContiguousArray<Value>, [Bool]) -> ParallelValueUpdate

    init(values: ContiguousArray<Value>, makeUpdate: @escaping (ContiguousArray<Value>, [Bool]) -> ParallelValueUpdate) {
        self.valuesCell = OwnerCell(values)
        self.makeUpdate = makeUpdate
    }

    @inlinable
    func set(_ value: Value, at index: Int) {
        if changedCell.value == nil {
            changedCell.value = Array(repeating: false, count: values.count)
        }
        values[index] = value
        changedCell.value?[index] = true
    }

    @usableFromInline
    func finish() -> ParallelValueUpdate? {
        guard let changed = changedCell.value else {
            return nil
        }
        return makeUpdate(values, changed)
    }
}
