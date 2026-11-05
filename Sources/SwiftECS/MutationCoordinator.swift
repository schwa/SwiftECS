import Observation

@usableFromInline
internal final class MutationCoordinator: Observable {
    private let registrar = ObservationRegistrar()
    private var revision: UInt64 = 0
    private var batchDepth = 0
    private var isDirty = false
    private var nextTokenID: UInt64 = 0
    private var handlers: [ObjectIdentifier: [UInt64: AnyObserverHandler]] = [:]
    @usableFromInline let suspended = OwnerCell(false)
    @inlinable var isParallelSuspended: Bool {
        get { suspended.value }
        set { suspended.value = newValue }
    }

    @inlinable
    func checkAccessible() {
        precondition(!isParallelSuspended, "World access is unavailable while parallel callbacks are running")
    }

    @usableFromInline
    var hasObservers: Bool {
        !handlers.isEmpty
    }

    @usableFromInline
    func access() {
        checkAccessible()
        registrar.access(self, keyPath: \.revision)
    }

    @inlinable
    func perform(_ write: () -> Void) {
        perform(write) {}
    }

    @inlinable
    func perform(_ write: () -> Void, events: () -> Void) {
        checkAccessible()
        write()
        defer { didChange() }
        events()
    }

    func batch<Result>(_ body: () throws -> Result) rethrows -> Result {
        beginBatch()
        defer { endBatch() }
        return try body()
    }

    func beginBatch() {
        checkAccessible()
        batchDepth += 1
    }

    func endBatch() {
        batchDepth -= 1
        if batchDepth == 0, isDirty {
            isDirty = false
            publish()
        }
    }

    @usableFromInline
    func didChange() {
        if batchDepth > 0 {
            isDirty = true
        } else {
            publish()
        }
    }

    private func publish() {
        registrar.withMutation(of: self, keyPath: \.revision) {
            revision &+= 1
        }
    }

    func observe<T: Component>(_ type: T.Type, handler: @escaping (ComponentEvent<T>) -> Void) -> ObservationToken {
        checkAccessible()
        let tokenID = nextTokenID
        nextTokenID += 1
        let typeID = ObjectIdentifier(type)
        handlers[typeID, default: [:]][tokenID] = ObserverHandler(handler: handler)
        return ObservationToken(id: tokenID, componentType: typeID)
    }

    func removeObserver(_ token: ObservationToken) {
        checkAccessible()
        switch token.kind {
        case .component:
            handlers[token.componentType]?.removeValue(forKey: token.id)
            if handlers[token.componentType]?.isEmpty == true {
                handlers.removeValue(forKey: token.componentType)
            }
        case .destroy:
            destroyHandlers.removeValue(forKey: token.id)
        case .relationship:
            relationshipHandlers[token.componentType]?.removeValue(forKey: token.id)
            if relationshipHandlers[token.componentType]?.isEmpty == true {
                relationshipHandlers.removeValue(forKey: token.componentType)
            }
        }
    }

    // MARK: - Destroy and relationship observers (#47)

    private var destroyHandlers: [UInt64: (EntityID) -> Void] = [:]
    private var relationshipHandlers: [ObjectIdentifier: [UInt64: (RelationshipEvent) -> Void]] = [:]

    var hasDestroyObservers: Bool {
        !destroyHandlers.isEmpty
    }

    func hasRelationshipObservers(_ type: RelationshipType) -> Bool {
        relationshipHandlers[type.id] != nil
    }

    func observeDestroyed(_ handler: @escaping (EntityID) -> Void) -> ObservationToken {
        checkAccessible()
        let tokenID = nextTokenID
        nextTokenID += 1
        destroyHandlers[tokenID] = handler
        return ObservationToken(id: tokenID, componentType: ObjectIdentifier(EntityID.self), kind: .destroy)
    }

    func observeRelationship(_ type: RelationshipType, handler: @escaping (RelationshipEvent) -> Void) -> ObservationToken {
        checkAccessible()
        let tokenID = nextTokenID
        nextTokenID += 1
        relationshipHandlers[type.id, default: [:]][tokenID] = handler
        return ObservationToken(id: tokenID, componentType: type.id, kind: .relationship)
    }

    func destroyed(_ entityID: EntityID) {
        for handler in destroyHandlers.values {
            handler(entityID)
        }
    }

    func relationshipChanged(_ type: RelationshipType, _ event: RelationshipEvent) {
        guard let subscribers = relationshipHandlers[type.id] else {
            return
        }
        for handler in subscribers.values {
            handler(event)
        }
    }

    func added<T: Component>(entity: Entity, component: T) {
        guard !handlers.isEmpty, let subscribers = handlers[ObjectIdentifier(T.self)] else {
            return
        }
        for handler in subscribers.values {
            handler.notifyAdded(entity: entity, component: component)
        }
    }

    func removed<T: Component>(entity: Entity, component: T) {
        guard !handlers.isEmpty, let subscribers = handlers[ObjectIdentifier(T.self)] else {
            return
        }
        for handler in subscribers.values {
            handler.notifyRemoved(entity: entity, component: component)
        }
    }

    @usableFromInline
    func changed<T: Component>(entity: Entity, component: T) {
        guard !handlers.isEmpty, let subscribers = handlers[ObjectIdentifier(T.self)] else {
            return
        }
        for handler in subscribers.values {
            handler.notifyChanged(entity: entity, component: component)
        }
    }
}
