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
    let componentType: ObjectIdentifier
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
