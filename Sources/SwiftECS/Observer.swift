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
    enum Kind: Hashable {
        case component
        case change
        case destroy
        case relationship
    }

    let id: UInt64
    // The component or relationship type observed; unused for destroy observers.
    let componentType: ObjectIdentifier
    var kind: Kind = .component
}

/// A component value replaced by a serial write. Parallel write-back is not reported, as with `ComponentEvent`.
public struct ComponentChange<T: Component> {
    public let entity: Entity
    public let oldValue: T
    public let newValue: T
}

/// A relationship edge added or removed. Not reported: edges removed because an entity was destroyed (observe that
/// with `World.observeDestroyed(_:)`) and edges copied by `World.clone(_:)`.
public enum RelationshipEvent: Hashable, Sendable {
    case added(source: EntityID, target: EntityID)
    case removed(source: EntityID, target: EntityID)
}

/// Type-erased observer handler.
@usableFromInline
protocol AnyObserverHandler: AnyObject {
    func notifyAdded(entity: Entity, component: any Component)
    func notifyRemoved(entity: Entity, component: any Component)
    func notifyChanged(entity: Entity, component: any Component)
}

/// Typed observer handler.
@usableFromInline
final class ObserverHandler<T: Component>: AnyObserverHandler {
    @usableFromInline let handler: (ComponentEvent<T>) -> Void

    init(handler: @escaping (ComponentEvent<T>) -> Void) {
        self.handler = handler
    }

    @usableFromInline
    func notifyAdded(entity: Entity, component: any Component) {
        guard let typed = component as? T else { return }
        handler(.added(entity, typed))
    }

    @usableFromInline
    func notifyRemoved(entity: Entity, component: any Component) {
        guard let typed = component as? T else { return }
        handler(.removed(entity, typed))
    }

    @usableFromInline
    func notifyChanged(entity: Entity, component: any Component) {
        guard let typed = component as? T else { return }
        handler(.changed(entity, typed))
    }
}
