internal struct ParallelColumnSnapshot<Value: ConcurrentComponent>: Sendable {
    let column: Column<Value>
    let values: ContiguousArray<Value>

    init(column: Column<Value>) {
        self.column = column
        values = column.snapshot()
    }

    func bind(in scope: SystemScope, indices: [Int]?) -> TaskColumn<Value> {
        let key = ObjectIdentifier(column)
        if let existing = scope.columns[key] as? TaskColumn<Value> {
            return existing
        }
        let selected = indices.map { indices in ContiguousArray(indices.map { values[$0] }) } ?? values
        let buffer = TaskColumn(values: selected) { values, changed in
            ParallelValueUpdate {
                column.apply(values, indices: indices, changed: changed)
            }
        }
        scope.columns[key] = buffer
        return buffer
    }
}
