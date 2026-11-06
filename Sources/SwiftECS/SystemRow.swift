/// One row of a system query with the given terms.
public typealias SystemRow<each Term: SystemTerm> = SystemOutputRow<repeat (each Term).Output>
