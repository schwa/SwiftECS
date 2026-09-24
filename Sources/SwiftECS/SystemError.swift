/// Errors that can occur when managing systems.
public enum SystemError: Error, Equatable {
    /// A system with this ID already exists.
    case duplicateID(SystemID)
    /// A dependency was not found.
    case dependencyNotFound(system: SystemID, dependency: SystemID)
    /// A cyclic dependency was detected.
    case cyclicDependency([SystemID])
    case excludedDependency(system: SystemID, dependency: SystemID)
    case invalidDependency(source: EntityID, target: EntityID)
    case missingPhase(SystemID)
    case invalidPhase(EntityID)
    case phaseCycle(EntityID)
    case invalidPipeline(EntityID)
}

// MARK: - CustomStringConvertible

extension SystemError: CustomStringConvertible {
    public var description: String {
        switch self {
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
