import Foundation
import Testing
@testable import UnifiedQuery

/// `normalizeLoose` の **言語固有 / プロパティ系** テスト。
///
/// (input → expected) の素朴な対は `spec/normalize.json` と `SpecDrivenTests` 側に
/// 寄せてある。ここに残るのは:
///   - 不等式アサーション(濁点・半濁点が「別キーである」ことの確認)
///   - idempotency(`normalize(normalize(x)) == normalize(x)`)
///   - 長文の性能スモーク(落ちないこと、空でないこと)
@Suite("normalizeLoose (native-only)")
struct NormalizeTests {
    // MARK: - Dakuten / handakuten distinguished

    @Test func dakutenAndUnvoicedAreDifferent() {
        // 「が」と「か」は別キーになる。
        #expect(normalizeLoose(input: "が") != normalizeLoose(input: "か"))
    }

    @Test func handakutenAndUnvoicedAreDifferent() {
        #expect(normalizeLoose(input: "ぱ") != normalizeLoose(input: "は"))
    }

    @Test func dakutenAndHandakutenAreDifferent() {
        // 「ば」と「ぱ」も区別。
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
