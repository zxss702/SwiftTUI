import Foundation

@MainActor class Weak<Value> where Value: AnyObject {
    weak var value: Value?

    init(value: Value?) {
        self.value = value
    }
}
