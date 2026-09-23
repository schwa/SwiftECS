protocol Component {}

final class Column<Value: Component> {
    var values: [Value]

    init(_ values: [Value]) {
        self.values = values
    }
}

func read<Value: Component>(_ column: Column<Value>, at index: Int) -> Value {
    column.values[index]
}

struct TypedReference<each Value: Component> {
    let columns: (repeat Column<each Value>)
    let index: Int

    init(index: Int, columns: repeat Column<each Value>) {
        self.index = index
        self.columns = (repeat each columns)
    }

    var values: (repeat each Value) {
        get {
            #if DIRECT_ACCESS
            return (repeat (each columns).values[index])
            #else
            return (repeat read(each columns, at: index))
            #endif
        }
        nonmutating set {
            set(repeat each newValue)
        }
    }

    func set(_ values: repeat each Value) {
        for (column, value) in repeat (each columns, each values) {
            column.values[index] = value
        }
    }
}

func makeReference<each Value: Component>(index: Int, columns: repeat Column<each Value>) -> TypedReference<repeat each Value> {
    TypedReference(index: index, columns: repeat each columns)
}

struct Position: Component { var x: Double }
struct Velocity: Component { var x: Double }
let positions = Column([Position(x: 1)])
let velocities = Column([Velocity(x: 2)])
let reference = makeReference(index: 0, columns: positions, velocities)
precondition(reference.values.0.x == 1)
reference.values = (Position(x: 3), Velocity(x: 4))
precondition(positions.values[0].x == 3)
precondition(velocities.values[0].x == 4)

let single = makeReference(index: 0, columns: positions)
#if SINGLE_ASSIGNMENT
single.values = Position(x: 5)
#else
single.set(Position(x: 5))
#endif
precondition(single.values.x == 5)
