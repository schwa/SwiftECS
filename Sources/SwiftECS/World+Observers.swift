extension World {
    /// Register an observer for serial writes that replace an existing component value, with the old and new
    /// values. Writers read the old value only while such an observer exists for the type.
    @discardableResult
    public func observeChanges<T: Component>(
        _ type: T.Type,
        handler: @escaping (ComponentChange<T>) -> Void
    ) -> ObservationToken {
        mutations.observeChanges(type, handler: handler)
    }

    /// Register an observer that runs after an entity is destroyed. Component observers get no events for the
    /// destroyed entity's components.
    @discardableResult
    public func observeDestroyed(_ handler: @escaping (EntityID) -> Void) -> ObservationToken {
        mutations.observeDestroyed(handler)
    }

    /// Register an observer for edges of one relationship type being added or removed.
    @discardableResult
    public func observeRelationship<R: Relationship>(
        _ type: R.Type,
        handler: @escaping (RelationshipEvent) -> Void
    ) -> ObservationToken {
        mutations.observeRelationship(RelationshipType(type), handler: handler)
    }
}
