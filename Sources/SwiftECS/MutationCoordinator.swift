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
        handlers[token.componentType]?.removeValue(forKey: token.id)
        if handlers[token.componentType]?.isEmpty == true {
            handlers.removeValue(forKey: token.componentType)
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
