/// Errors that can occur when managing systems.
public enum SystemError: Error, Equatable {
    /// A system with this ID already exists.
    case duplicateID(SystemID)
    /// A dependency was not found.
    case dependencyNotFound(system: SystemID, dependency: SystemID)
    /// A cyclic dependency was detected.
    case cyclicDependency([SystemID])
    /// A system depends on a system that the pipeline does not select.
    case excludedDependency(system: SystemID, dependency: SystemID)
    /// A ``DependsOn`` link connects entities that are not both systems or both phases.
    case invalidDependency(source: EntityID, target: EntityID)
    /// A system does not belong to exactly one phase.
    case missingPhase(SystemID)
    /// The entity is not a phase.
    case invalidPhase(EntityID)
    /// Phase dependencies form a cycle.
    case phaseCycle(EntityID)
    /// The entity has no ``Pipeline`` component.
    case invalidPipeline(EntityID)
    /// A system component is a class. System components must have value semantics.
    case referenceComponent(ComponentType)
    /// A query names the same component type twice.
    case duplicateTerm(ComponentType)
    /// A deferred set targets an entity that no longer exists.
    case missingCommandEntity(EntityID)
    /// The parallelism is not positive.
    case invalidParallelism
    /// The minimum rows per task is not positive.
    case invalidPartitionSize
    /// Another run already owns the world.
    case parallelRunInProgress
}

// MARK: - CustomStringConvertible

extension SystemError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidParallelism:
            return "Parallelism must be positive"
        case .invalidPartitionSize:
            return "Minimum rows per task must be positive"
        case .parallelRunInProgress:
            return "A run already owns this world"
        case .missingCommandEntity(let id):
            return "Command target \(id) no longer exists"
        case .referenceComponent(let type):
            return "System components must have value semantics; \(type) is a class"
        case .duplicateTerm(let type):
            return "System query contains duplicate component \(type)"
        case .duplicateID(let id):
            return "System with ID '\(id)' already exists"
        case let .dependencyNotFound(system, dependency):
            return "System '\(system)' depends on '\(dependency)' which was not found"
        case let .excludedDependency(system, dependency):
            return "System '\(system)' requires excluded system '\(dependency)'"
        case let .invalidDependency(source, target):
            return "Invalid scheduling dependency from \(source) to \(target)"
        case .missingPhase(let system):
            return "System '\(system)' has no phase"
        case .invalidPhase(let entity):
            return "Entity \(entity) is not a phase"
        case .phaseCycle(let entity):
            return "Phase dependency cycle at \(entity)"
        case .invalidPipeline(let entity):
            return "Entity \(entity) has no pipeline"
        case .cyclicDependency(let cycle):
            let path = cycle.map(\.value).joined(separator: " -> ")
            return "Cyclic dependency detected: \(path)"
        }
    }
}
