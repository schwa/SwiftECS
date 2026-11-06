/// An iterator over rows of a system query with the given terms.
public typealias SystemRowIterator<each Term: SystemTerm> = SystemOutputIterator<repeat (each Term).Output>
