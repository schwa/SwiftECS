/// Events that can occur on components.
public enum ComponentEvent<T: Component> {
    /// A component was added to an entity.
    case added(Entity, T)
    /// A component was removed from an entity.
    case removed(Entity, T)
    /// A component was changed on an entity.
    case changed(Entity, T)
}

/// Token returned when registering an observer. Use to unregister.
public struct ObservationToken: Hashable {
    let id: UInt64
    let componentType: ComponentType

    init(id: UInt64, componentType: ComponentType) {
        self.id = id
        self.componentType = componentType
    }
}

/// Type-erased observer handler.
protocol AnyObserverHandler: AnyObject {
    func notifyAdded(entity: Entity, component: any Component)
    func notifyRemoved(entity: Entity, component: any Component)
    func notifyChanged(entity: Entity, component: any Component)
}

/// Typed observer handler.
final class ObserverHandler<T: Component>: AnyObserverHandler {
    let handler: (ComponentEvent<T>) -> Void

    init(handler: @escaping (ComponentEvent<T>) -> Void) {
        self.handler = handler
    }

    func notifyAdded(entity: Entity, component: any Component) {
        guard let typed = component as? T else { return }
        handler(.added(entity, typed))
    }

    func notifyRemoved(entity: Entity, component: any Component) {
        guard let typed = component as? T else { return }
        handler(.removed(entity, typed))
    }

    func notifyChanged(entity: Entity, component: any Component) {
        guard let typed = component as? T else { return }
        handler(.changed(entity, typed))
    }
}

/// Manages component observers for a World.
final class ObserverRegistry {
    private var nextTokenId: UInt64 = 0
    private var handlers: [ComponentType: [UInt64: AnyObserverHandler]] = [:]

    /// Register an observer for a component type.
    func observe<T: Component>(
        _ type: T.Type,
        handler: @escaping (ComponentEvent<T>) -> Void
    ) -> ObservationToken {
        let tokenId = nextTokenId
        nextTokenId += 1

        let componentType = ComponentType(type)
        let observerHandler = ObserverHandler(handler: handler)

        if handlers[componentType] == nil {
            handlers[componentType] = [:]
        }
        handlers[componentType]![tokenId] = observerHandler

        return ObservationToken(id: tokenId, componentType: componentType)
    }

    /// Unregister an observer.
    func removeObserver(_ token: ObservationToken) {
        handlers[token.componentType]?.removeValue(forKey: token.id)
    }

    /// Notify observers that a component was added.
    func notifyAdded<T: Component>(entity: Entity, component: T) {
        let componentType = ComponentType(T.self)
        guard let typeHandlers = handlers[componentType] else { return }
        for (_, handler) in typeHandlers {
            handler.notifyAdded(entity: entity, component: component)
        }
    }

    /// Notify observers that a component was removed.
    func notifyRemoved<T: Component>(entity: Entity, component: T) {
        let componentType = ComponentType(T.self)
        guard let typeHandlers = handlers[componentType] else { return }
        for (_, handler) in typeHandlers {
            handler.notifyRemoved(entity: entity, component: component)
        }
    }

    /// Notify observers that a component was changed.
    func notifyChanged<T: Component>(entity: Entity, component: T) {
        let componentType = ComponentType(T.self)
        guard let typeHandlers = handlers[componentType] else { return }
        for (_, handler) in typeHandlers {
            handler.notifyChanged(entity: entity, component: component)
        }
    }

    /// Check if there are any observers for a component type.
    func hasObservers<T: Component>(for type: T.Type) -> Bool {
        let componentType = ComponentType(type)
        guard let typeHandlers = handlers[componentType] else { return false }
        return !typeHandlers.isEmpty
    }
}
