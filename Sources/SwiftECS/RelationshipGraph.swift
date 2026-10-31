// Single internal owner of relationship index state.
//
// It owns the per-type `RelationshipStorage` map and the only forward/reverse
// index mutations, so callers never create storage or reach into the map. The
// `Entity` API expresses cardinality and cycle policy on top of these
// primitives, and observation is wrapped by callers through the mutation
// coordinator. Reads and pure writes here perform no observation of their own.
internal final class RelationshipGraph {
    private var storages: [RelationshipType: RelationshipStorage] = [:]

    private func storage(_ type: RelationshipType) -> RelationshipStorage {
        if let existing = storages[type] {
            return existing
        }
        let created = RelationshipStorage()
        storages[type] = created
        return created
    }

    // MARK: - Reads

    func targets(_ type: RelationshipType, from source: EntityID) -> [EntityID] {
        storages[type]?.targets(from: source) ?? []
    }

    func sources(_ type: RelationshipType, to target: EntityID) -> [EntityID] {
        storages[type]?.sources(to: target) ?? []
    }

    func contains(_ type: RelationshipType, source: EntityID, target: EntityID?) -> Bool {
        storages[type]?.contains(source: source, target: target) ?? false
    }

    func traverse(_ type: RelationshipType, from source: EntityID, reversed: Bool) -> [EntityID] {
        storages[type]?.traverse(from: source, reversed: reversed) ?? []
    }

    func reaches(_ type: RelationshipType, from source: EntityID, to target: EntityID) -> Bool {
        storages[type]?.reaches(from: source, to: target) ?? false
    }

    func snapshot(_ type: RelationshipType) -> (outgoing: [EntityID: [EntityID]], incoming: [EntityID: [EntityID]]) {
        storages[type]?.snapshot() ?? ([:], [:])
    }

    // MARK: - Writes (pure; callers wrap observation)

    func insert(_ type: RelationshipType, source: EntityID, target: EntityID) {
        storage(type).insert(source: source, target: target)
    }

    @discardableResult
    func remove(_ type: RelationshipType, source: EntityID, target: EntityID) -> Bool {
        storages[type]?.remove(source: source, target: target) ?? false
    }

    func removeOutgoing(_ type: RelationshipType, source: EntityID) {
        storages[type]?.removeOutgoing(from: source)
    }

    // Remove all incident links of an entity across every relationship type.
    func removeEntity(_ entity: EntityID) {
        for storage in storages.values {
            storage.removeEntity(entity)
        }
    }

    // Copy an entity's outgoing links to a clone, preserving original targets.
    func copyOutgoing(from source: EntityID, to destination: EntityID) {
        for storage in storages.values {
            for target in storage.targets(from: source) {
                storage.insert(source: destination, target: target)
            }
        }
    }
}
