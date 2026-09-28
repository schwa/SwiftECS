@testable import SwiftECS
import Testing

private final class CellValue {}

@Test func `owner cells release their initialized value`() {
    weak var reference: CellValue?
    do {
        let value = CellValue()
        reference = value
        let cell = OwnerCell(value)
        #expect(cell.value === value)
    }
    #expect(reference == nil)
}

@Test func `owner cells retain normal value copy semantics`() {
    let cell = OwnerCell([1, 2])
    let copy = cell.value
    cell.value.append(3)
    cell.value[0] = 4
    #expect(copy == [1, 2])
    #expect(cell.value == [4, 2, 3])
}
