/// The rows of a system query with the given terms.
public typealias SystemRows<each Term: SystemTerm> = SystemOutputRows<repeat (each Term).Output>
