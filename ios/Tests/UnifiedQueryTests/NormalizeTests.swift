import Foundation
import Testing
@testable import UnifiedQuery

/// **Language-specific / property-style** tests for `normalizeLoose`.
///
/// Plain (input → expected) pairs live in `spec/normalize.json` and
/// `SpecDrivenTests`. What remains here:
///   - inequality assertions (dakuten/handakuten produce distinct keys)
///   - idempotency (`normalize(normalize(x)) == normalize(x)`)
///   - long-input smoke (doesn't crash, doesn't return empty)
@Suite("normalizeLoose (native-only)")
struct NormalizeTests {
    // MARK: - Dakuten / handakuten distinguished

    @Test func dakutenAndUnvoicedAreDifferent() {
        // 「が」 and 「か」 must hash to different keys.
        #expect(normalizeLoose(input: "が") != normalizeLoose(input: "か"))
    }

    @Test func handakutenAndUnvoicedAreDifferent() {
        #expect(normalizeLoose(input: "ぱ") != normalizeLoose(input: "は"))
    }

    @Test func dakutenAndHandakutenAreDifferent() {
        // 「ば」 and 「ぱ」 are also distinct.
        #expect(normalizeLoose(input: "ば") != normalizeLoose(input: "ぱ"))
    }

    // MARK: - Idempotency

    @Test func normalizeIsIdempotent() {
        let samples = [
            "", "hello", "Hello WORLD", "東京", "ｶﾞｯｺｳ", "ヴァイオリン",
            "Ｐｙｔｈｏｎ 入門", "東京 ﾄｳｷｮｳ Tokyo", "コーヒー", "🍣"
        ]
        for s in samples {
            let once = normalizeLoose(input: s)
            let twice = normalizeLoose(input: once)
            #expect(once == twice, "non-idempotent for \"\(s)\"")
        }
    }

    // MARK: - Performance smoke

    @Test func longStringDoesNotExplode() {
        let long = String(repeating: "東京タワー ｶﾞｯｺｳ Tokyo123 ", count: 1000)
        let n = normalizeLoose(input: long)
        #expect(!n.isEmpty)
        #expect(normalizeLoose(input: n) == n)
    }
}
