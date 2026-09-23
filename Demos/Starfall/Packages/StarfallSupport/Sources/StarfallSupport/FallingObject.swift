import ECS

struct FallingObject: Component {
    enum Kind {
        case star, meteor
    }

    var kind: Kind
}
