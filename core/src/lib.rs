mod engine;
mod normalize;

pub use engine::{Hit, SearchEngine, SearchError};
pub use normalize::normalize_loose;

uniffi::setup_scaffolding!();

/// Exposed through FFI so the normalized form can be inspected for testing and debugging.
#[uniffi::export(name = "normalizeLoose")]
pub fn normalize_loose_ffi(input: String) -> String {
    normalize_loose(&input)
}
