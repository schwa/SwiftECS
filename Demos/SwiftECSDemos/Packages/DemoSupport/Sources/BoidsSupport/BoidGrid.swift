// An immutable spatial index of every boid at the start of a frame. Steering reads neighbors from here, so
// each boid sees last frame's flock no matter which worker updates it first.
struct BoidGrid: Sendable {
    let positions: [SIMD2<Double>]
    let velocities: [SIMD2<Double>]
    let bounds: SIMD2<Double>
    let columns: Int
    let rows: Int
    let cellSize: Double
    // Boid indices sorted by cell. Cell `c` holds `order[cellStart[c]..<cellStart[c + 1]]`.
    let cellStart: [Int]
    let order: [Int]

    static let empty = Self(boids: [])

    init(boids: [Boid], bounds: SIMD2<Double> = BoidsSettings.bounds, cellSize: Double = BoidsSettings.neighborRadius) {
        let columns = max(1, Int(bounds.x / cellSize))
        let rows = max(1, Int(bounds.y / cellSize))
        self.bounds = bounds
        self.columns = columns
        self.rows = rows
        self.cellSize = cellSize
        positions = boids.map(\.position)
        velocities = boids.map(\.velocity)

        let cells = positions.map { Self.cell(of: $0, columns: columns, rows: rows, cellSize: cellSize) }
        var start = [Int](repeating: 0, count: columns * rows + 1)
        for cell in cells {
            start[cell + 1] += 1
        }
        for index in 1..<start.count {
            start[index] += start[index - 1]
        }
        var next = start
        var order = [Int](repeating: 0, count: cells.count)
        for (boid, cell) in cells.enumerated() {
            order[next[cell]] = boid
            next[cell] += 1
        }
        cellStart = start
        self.order = order
    }

    static func cell(of position: SIMD2<Double>, columns: Int, rows: Int, cellSize: Double) -> Int {
        let column = min(columns - 1, max(0, Int(position.x / cellSize)))
        let row = min(rows - 1, max(0, Int(position.y / cellSize)))
        return row * columns + column
    }

    // Calls `body` with each boid in the 3x3 block of cells around `position`, with the shortest offset to it
    // across the wrapped edges.
    func forEachNeighbor(of position: SIMD2<Double>, _ body: (SIMD2<Double>, SIMD2<Double>) -> Void) {
        let center = Self.cell(of: position, columns: columns, rows: rows, cellSize: cellSize)
        let centerColumn = center % columns
        let centerRow = center / columns
        for rowOffset in -1...1 {
            let row = (centerRow + rowOffset + rows) % rows
            for columnOffset in -1...1 {
                let cell = row * columns + (centerColumn + columnOffset + columns) % columns
                for slot in cellStart[cell]..<cellStart[cell + 1] {
                    let boid = order[slot]
                    var offset = positions[boid] - position
                    offset -= bounds * (offset / bounds).rounded(.toNearestOrAwayFromZero)
                    body(offset, velocities[boid])
                }
            }
        }
    }
}
