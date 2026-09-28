public protocol SystemInput {
    associatedtype Value
    var binding: SystemBinding<Value> { get }
}
