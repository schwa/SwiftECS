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

/// A component value replaced by a serial write. Parallel write-back is not reported, as with ``ComponentEvent``.
public struct ComponentChange<T: Component> {
    /// The entity whose component changed.
    public let entity: Entity
    /// The value before the write.
    public let oldValue: T
    /// The value after the write.
    public let newValue: T
}

/// A relationship edge added or removed. Not reported: edges removed because an entity was destroyed (observe that
/// with ``World/observeDestroyed(_:)``) and edges copied by ``World/clone(_:)``.
public enum RelationshipEvent: Hashable, Sendable {
    /// A link from the source to the target was added.
    case added(source: EntityID, target: EntityID)
    /// A link from the source to the target was removed.
    case removed(source: EntityID, target: EntityID)
}

/// Type-erased observer handler.
@usableFromInline
protocol AnyObserverHandler: AnyObject {}

/// Typed observer handler.
@usableFromInline
final class ObserverHandler<T: Component>: AnyObserverHandler {
    @usableFromInline let handler: (ComponentEvent<T>) -> Void

    init(handler: @escaping (ComponentEvent<T>) -> Void) {
        self.handler = handler
    }
}
