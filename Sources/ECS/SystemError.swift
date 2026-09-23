/// Errors that can occur when managing systems.
public enum SystemError: Error, Equatable {
    /// A system with this ID already exists.
    case duplicateID(SystemID)
    /// A dependency was not found.
    case dependencyNotFound(system: SystemID, dependency: SystemID)
    /// A cyclic dependency was detected.
    case cyclicDependency([SystemID])
}

// MARK: - CustomStringConvertible

extension SystemError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .duplicateID(let id):
            return "System with ID '\(id)' already exists"
        case let .dependencyNotFound(system, dependency):
            return "System '\(system)' depends on '\(dependency)' which was not found"
        case .cyclicDependency(let cycle):
            let path = cycle.map(\.value).joined(separator: " -> ")
            return "Cyclic dependency detected: \(path)"
        }
    }
}
