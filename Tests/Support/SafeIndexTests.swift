import Foundation
import Testing

@testable import PRism

@Suite("Bezpečný index")
struct SafeIndexTests {
    @Test("Prvek v rozsahu se vrátí, mimo rozsah je nil")
    func returnsElementInsideAndNilOutside() {
        let items = ["a", "b"]

        #expect(items[safely: 0] == "a")
        #expect(items[safely: 1] == "b")
        #expect(items[safely: 2] == nil)
        #expect(items[safely: -1] == nil)
        #expect([String]()[safely: 0] == nil)
    }
}
