import SwiftECS
import Testing

private struct Marker: Component {}

// #46: identity is the type alone; the name is for debugging.
@Test
func componentTypeIdentityIgnoresName() {
    let id = ObjectIdentifier(Marker.self)
    let first = ComponentType(id, name: "First")
    let second = ComponentType(id, name: "Second")
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
    #expect(ComponentType(Marker.self) == first)
}

@Test
func componentTypeNameStillDescribesTheType() {
    #expect(ComponentType(Marker.self).name == "Marker")
    #expect(ComponentType(Marker.self).description == "Marker")
    #expect(ComponentType(ObjectIdentifier(Marker.self), name: "Custom").name == "Custom")
}
