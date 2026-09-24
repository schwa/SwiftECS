import Collections

internal final class RelationshipStorage {
    private var outgoing: [EntityID: OrderedSet<EntityID>] = [:]
    private var incoming: [EntityID: OrderedSet<EntityID>] = [:]

    func targets(from source: EntityID) -> [EntityID] {
        Array(outgoing[source] ?? [])
    }

    func sources(to target: EntityID) -> [EntityID] {
        Array(incoming[target] ?? [])
    }

    func contains(source: EntityID, target: EntityID?) -> Bool {
        guard let targets = outgoing[source] else {
            return false
        }
        if let target {
            return targets.contains(target)
        }
        return !targets.isEmpty
    }

    func insert(source: EntityID, target: EntityID) {
        outgoing[source, default: []].append(target)
        incoming[target, default: []].append(source)
    }

    @discardableResult
    func remove(source: EntityID, target: EntityID) -> Bool {
        guard outgoing[source]?.remove(target) != nil else {
            return false
        }
        incoming[target]?.remove(source)
        if outgoing[source]?.isEmpty == true {
            outgoing.removeValue(forKey: source)
        }
        if incoming[target]?.isEmpty == true {
            incoming.removeValue(forKey: target)
        }
        return true
    }

    func removeOutgoing(from source: EntityID) {
        for target in targets(from: source) {
            remove(source: source, target: target)
        }
    }

    func removeEntity(_ entity: EntityID) {
        removeOutgoing(from: entity)
        for source in sources(to: entity) {
            remove(source: source, target: entity)
        }
    }

    func traverse(from root: EntityID, reversed: Bool) -> [EntityID] {
        var visited: Set<EntityID> = [root]
        var queue = [root]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            let neighbors = reversed ? sources(to: current) : targets(from: current)
            for neighbor in neighbors where visited.insert(neighbor).inserted {
                queue.append(neighbor)
            }
        }
        return Array(queue.dropFirst())
    }

    func reaches(from source: EntityID, to target: EntityID) -> Bool {
        if source == target {
            return true
        }
        var visited: Set<EntityID> = [source]
        var queue = [source]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            for neighbor in targets(from: current) {
                if neighbor == target {
                    return true
                }
                if visited.insert(neighbor).inserted {
                    queue.append(neighbor)
                }
            }
        }
        return false
    }
}
