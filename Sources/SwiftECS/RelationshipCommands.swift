/// Deferred add and remove commands for one relationship type. Supplied by ``EditRelationship``.
///
/// Endpoints and relationship constraints are checked when the commands merge.
public struct RelationshipCommands<Link: Relationship> {
    internal let scope: SystemScope
    internal var parallelAdd: ((EntityID, EntityID) -> Void)?
    internal var parallelRemove: ((EntityID, EntityID) -> Void)?

    /// Adds a link from the source to the target when commands merge.
    public func add(from source: EntityID, to target: EntityID) {
        scope.checkActive()
        if let parallelAdd {
            parallelAdd(source, target)
        } else {
            SystemCommands(scope: scope).addRelationship(Link.self, from: source, to: target)
        }
    }

    /// Removes the link from the source to the target when commands merge.
    public func remove(from source: EntityID, to target: EntityID) {
        scope.checkActive()
        if let parallelRemove {
            parallelRemove(source, target)
        } else {
            SystemCommands(scope: scope).removeRelationship(Link.self, from: source, to: target)
        }
    }
}
