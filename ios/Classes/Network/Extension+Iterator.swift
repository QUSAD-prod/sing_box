import Foundation
import Libbox

// Utility for converting iterators to arrays
// Will be used with Libbox iterators

public extension LibboxStringIteratorProtocol {
    func toArray() -> [String] {
        var array: [String] = []
        while hasNext() {
            array.append(next())
        }
        return array
    }
}

