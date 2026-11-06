/// A relationship that parallel systems can read and edit from worker tasks.
public protocol ConcurrentRelationship: Relationship, SendableMetatype {}
