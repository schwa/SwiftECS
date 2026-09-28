internal struct ScheduledSystem {
    let entityID: EntityID
    let descriptor: SystemDescriptor
    let predecessors: Set<EntityID>
}
