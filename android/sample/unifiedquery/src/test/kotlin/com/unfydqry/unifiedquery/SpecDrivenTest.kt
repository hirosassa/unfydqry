package com.unfydqry.unifiedquery

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource
import java.util.stream.Stream
import uniffi.unfydqry.SearchEngine
import uniffi.unfydqry.normalizeLoose

/**
 * Materializes the "golden tests" from design doc §E.4 in the form of
 * spec/normalize.json and spec/search.json. Reads the same JSON files as the
 * Swift and Rust suites, so any drift in the Rust core's normalization or
 * search logic causes all three runners (Swift / Kotlin / Rust) to fail at the
 * same `id` simultaneously.
 */
@DisplayName("Spec-driven cross-platform")
class SpecDrivenTest {
    companion object {
        @JvmStatic
        fun normalizeCases(): Stream<Arguments> =
            Spec.normalize.cases.stream().map {
                Arguments.of(it.id, it.description, it.input, it.expected)
            }

        @JvmStatic
        fun scenarios(): Stream<Arguments> =
            Spec.search.scenarios.stream().map { Arguments.of(it.id, it) }

        @JvmStatic
        fun matrixQueries(): Stream<Arguments> =
            Spec.search.seededMatrices.stream().flatMap { m ->
                m.queries.stream().map { q ->
                    Arguments.of("${m.id}/${q.query}", m, q)
                }
            }

        private fun apply(ops: List<IndexOp>, engine: SearchEngine) {
            for (op in ops) {
                when (op.op) {
                    "index" -> engine.index(op.id, op.text ?: "")
                    "remove" -> engine.remove(op.id)
                    else -> error("Unknown op \"${op.op}\" — spec/search.json schema mismatch")
                }
            }
        }
    }

    @Test fun `normalize spec version is expected`() {
        assertEquals(Spec.EXPECTED_VERSION, Spec.normalize.version)
    }

    @Test fun `search spec version is expected`() {
        assertEquals(Spec.EXPECTED_VERSION, Spec.search.version)
    }

    @ParameterizedTest(name = "{0}: {1}")
    @MethodSource("normalizeCases")
    fun `normalize matches spec`(id: String, description: String, input: String, expected: String) {
        assertEquals(expected, normalizeLoose(input), "id=$id: $description")
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("scenarios")
    fun `scenario matches spec`(id: String, s: Scenario) {
        val engine = SearchEngine(":memory:")
        apply(s.ops, engine)
        for (assertion in s.assertions) {
            val got = engine.search(assertion.search.query, assertion.search.limit.toUInt())
                .map { it.id }.toSet()
            val want = assertion.expectedIds.toSet()
            assertEquals(want, got,
                "scenario id=${s.id}: ${s.description}; " +
                "query=\"${assertion.search.query}\" got=${got.sorted()} want=${want.sorted()}")
        }
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("matrixQueries")
    fun `seeded matrix query matches spec`(label: String, m: SeededMatrix, q: QueryExpectation) {
        val engine = SearchEngine(":memory:")
        apply(m.seed, engine)
        val got = engine.search(q.query, m.limit.toUInt()).map { it.id }.toSet()
        val want = q.expectedIds.toSet()
        assertEquals(want, got,
            "matrix=${m.id} query=\"${q.query}\": ${q.description}; " +
            "got=${got.sorted()} want=${want.sorted()}")
    }

    @Test fun `loaded normalize cases are non-empty`() {
        assertTrue(Spec.normalize.cases.isNotEmpty(), "normalize.json had zero cases")
    }

    @Test fun `loaded scenarios are non-empty`() {
        assertTrue(Spec.search.scenarios.isNotEmpty(), "search.json had zero scenarios")
    }
}
