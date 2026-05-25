//! Cross-platform conformance runner.
//!
//! Reads the same `spec/normalize.json` and `spec/search.json` that the Swift
//! and Kotlin test suites read, and asserts the same expectations directly
//! against the in-process Rust API. This catches drift inside the core
//! independently of either FFI binding.
//!
//! Layout assumption: this file lives at `core/tests/conformance.rs` and
//! `spec/` is its sibling at the workspace root (`../spec/`).

use std::collections::BTreeSet;
use std::path::PathBuf;

use serde::Deserialize;

use unfydqry::{normalize_loose, SearchEngine};

const EXPECTED_VERSION: u32 = 1;

fn spec_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("spec")
}

fn read_spec<T: for<'de> Deserialize<'de>>(name: &str) -> T {
    let path = spec_dir().join(format!("{name}.json"));
    let s =
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_str(&s).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
}

// ---------------------------------------------------------------------------
// normalize.json
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct NormalizeCase {
    id: String,
    description: String,
    input: String,
    expected: String,
    #[serde(default)]
    #[allow(dead_code)]
    source: Option<String>,
}

#[derive(Deserialize)]
struct NormalizeSpec {
    version: u32,
    cases: Vec<NormalizeCase>,
}

#[test]
fn normalize_spec_matches() {
    let spec: NormalizeSpec = read_spec("normalize");
    assert_eq!(
        spec.version, EXPECTED_VERSION,
        "spec/normalize.json version mismatch — loader expects {EXPECTED_VERSION}",
    );
    assert!(!spec.cases.is_empty(), "spec/normalize.json had zero cases");
    for c in spec.cases {
        let got = normalize_loose(&c.input);
        assert_eq!(
            got, c.expected,
            "normalize id={}: {}\n  input={:?}\n  got={:?}\n  want={:?}",
            c.id, c.description, c.input, got, c.expected
        );
    }
}

// ---------------------------------------------------------------------------
// search.json
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct IndexOp {
    op: String,
    id: i64,
    #[serde(default)]
    text: Option<String>,
}

#[derive(Deserialize)]
struct SearchSpec {
    query: String,
    limit: u32,
}

#[derive(Deserialize)]
struct Assertion {
    search: SearchSpec,
    expected_ids: Vec<i64>,
}

#[derive(Deserialize)]
struct Scenario {
    id: String,
    description: String,
    ops: Vec<IndexOp>,
    assertions: Vec<Assertion>,
}

#[derive(Deserialize)]
struct QueryExpectation {
    query: String,
    description: String,
    expected_ids: Vec<i64>,
}

#[derive(Deserialize)]
struct SeededMatrix {
    id: String,
    #[allow(dead_code)]
    description: String,
    limit: u32,
    seed: Vec<IndexOp>,
    queries: Vec<QueryExpectation>,
}

#[derive(Deserialize)]
struct SearchSpecFile {
    version: u32,
    scenarios: Vec<Scenario>,
    seeded_matrices: Vec<SeededMatrix>,
}

fn apply_ops(engine: &SearchEngine, ops: &[IndexOp]) {
    for op in ops {
        match op.op.as_str() {
            "index" => engine
                .index(op.id, op.text.clone().unwrap_or_default())
                .expect("index"),
            "remove" => engine.remove(op.id).expect("remove"),
            other => panic!("unknown op {other:?} — spec/search.json schema mismatch"),
        }
    }
}

#[test]
fn search_scenarios_match() {
    let spec: SearchSpecFile = read_spec("search");
    assert_eq!(spec.version, EXPECTED_VERSION);
    assert!(
        !spec.scenarios.is_empty(),
        "spec/search.json had zero scenarios"
    );

    for s in spec.scenarios {
        let engine = SearchEngine::new(":memory:".to_string()).expect("open engine");
        apply_ops(&engine, &s.ops);
        for a in &s.assertions {
            let hits = engine
                .search(a.search.query.clone(), a.search.limit)
                .expect("search");
            let got: BTreeSet<i64> = hits.iter().map(|h| h.id).collect();
            let want: BTreeSet<i64> = a.expected_ids.iter().copied().collect();
            assert_eq!(
                got, want,
                "scenario id={}: {}\n  query={:?}\n  got={:?}\n  want={:?}",
                s.id, s.description, a.search.query, got, want
            );
        }
    }
}

#[test]
fn seeded_matrices_match() {
    let spec: SearchSpecFile = read_spec("search");
    assert!(
        !spec.seeded_matrices.is_empty(),
        "spec/search.json had zero seeded_matrices"
    );

    for m in spec.seeded_matrices {
        let engine = SearchEngine::new(":memory:".to_string()).expect("open engine");
        apply_ops(&engine, &m.seed);
        for q in &m.queries {
            let hits = engine.search(q.query.clone(), m.limit).expect("search");
            let got: BTreeSet<i64> = hits.iter().map(|h| h.id).collect();
            let want: BTreeSet<i64> = q.expected_ids.iter().copied().collect();
            assert_eq!(
                got, want,
                "matrix id={} query={:?}: {}\n  got={:?}\n  want={:?}",
                m.id, q.query, q.description, got, want
            );
        }
    }
}
