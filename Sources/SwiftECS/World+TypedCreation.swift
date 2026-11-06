extension World {
    /// Writes one component of an entity being created with `createEntity(id:types:_:)`.
    public struct EntityInitializer {
        @usableFromInline let archetype: Archetype
        @usableFromInline let index: Int

        /// Sets one component of the new entity.
        @inlinable
        public func set<T: Component>(_ component: T) {
            archetype.setSerialComponent(component, at: index)
        }
    }

    /// Creates an entity from component types known only at run time, setting each component through a typed call.
    ///
    /// Unlike `createEntity(id:components:)`, no component is boxed as `any Component`.
    ///
    /// - Precondition: `id` is not in use, and `fill` sets exactly the components in `types`, once each.
    @discardableResult
    public func createEntity(
        id: EntityID, types: [ComponentType], _ fill: (EntityInitializer) -> Void
    ) -> Entity {
        precondition(entityLocations[id] == nil, "Entity ID already exists")
        let archetype: Archetype
        if let cached = lastTypedCreation, !cached.archetype.isReclaimed, cached.types == types {
            archetype = cached.archetype
        } else {
            let signature = ArchetypeSignature(Set(types))
            precondition(signature.types.count == types.count, "Component types must be unique")
            archetype = getOrCreateArchetype(signature)
            lastTypedCreation = (types, archetype)
        }
        mutations.perform {
            let index = archetype.addEntity(id)
            fill(EntityInitializer(archetype: archetype, index: index))
            precondition(
                archetype.columns.count == types.count && archetype.columns.values.allSatisfy { $0.count == index + 1 },
                "createEntity(id:types:_:) must set every listed component once"
            )
            entityLocations[id] = EntityLocation(archetype: archetype, index: index)
            structuralRevision &+= 1
        }
        return Entity(id: id, world: self)
    }
}
