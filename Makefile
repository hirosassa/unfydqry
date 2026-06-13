# Developer convenience targets that mirror the GitHub Actions checks.
# Run `make setup` once per clone; run `make check` before pushing; run
# `make gen-bindings` after changing any FFI-facing Rust signature, then commit
# the regenerated bindings.

CORE          := core
DARWIN        := aarch64-apple-darwin
DYLIB         := target/$(DARWIN)/release/libunfydqry.dylib
KOTLIN_OUT    := android/sample/unifiedquery/src/main/kotlin/uniffi/unfydqry/unfydqry.kt
SWIFT_OUT     := ios/Sources/UnifiedQuery/UnifiedQuery.swift
HOOKS_PATH    := .githooks

.PHONY: setup ensure-hooks fmt fmt-check clippy test check dylib gen-bindings verify-bindings ci

## --- Repo setup ---

# core.hooksPath is local git config: it is NOT carried by clone/pull, so every
# clone must enable it once. `setup` is the explicit entry point; `ensure-hooks`
# is a quiet, idempotent self-heal that the day-to-day targets depend on, so
# anyone who runs `make check`/`make ci`/`make gen-bindings` gets the hooks wired
# up automatically — including people who cloned before the hooks existed.

setup: ensure-hooks ## Configure this clone for development (enables git hooks).
	@echo "setup: this clone is ready (git hooks enabled)."

ensure-hooks: ## Point git at .githooks if it isn't already (idempotent).
	@if [ "$$(git config --get core.hooksPath)" != "$(HOOKS_PATH)" ]; then \
		git config core.hooksPath $(HOOKS_PATH); \
		echo "ensure-hooks: set core.hooksPath=$(HOOKS_PATH)"; \
	fi

## --- Rust core (mirrors .github/workflows/rust-tests.yml) ---

fmt: ## Format the Rust core in place.
	cd $(CORE) && cargo fmt --all

fmt-check: ## Fail if the Rust core is not rustfmt-clean.
	cd $(CORE) && cargo fmt --all -- --check

clippy: ## Lint with warnings treated as errors.
	cd $(CORE) && cargo clippy --all-targets -- -D warnings

test: ## Run unit + conformance tests.
	cd $(CORE) && cargo test --all-targets

check: ensure-hooks fmt-check clippy test ## All Rust CI checks at once.

## --- UniFFI bindings (mirrors kotlin-tests.yml / swift-tests.yml drift checks) ---

dylib: ## Build the macOS dylib that uniffi-bindgen reads.
	cd $(CORE) && cargo build --release --target $(DARWIN)

gen-bindings: ensure-hooks dylib ## Regenerate the committed Swift + Kotlin bindings in place.
	cd $(CORE) && cargo run --bin uniffi-bindgen -- generate \
		--library $(DYLIB) --language kotlin --out-dir generated/kotlin
	cp $(CORE)/generated/kotlin/uniffi/unfydqry/unfydqry.kt $(KOTLIN_OUT)
	cd $(CORE) && cargo run --bin uniffi-bindgen -- generate --no-format \
		--library $(DYLIB) --language swift --out-dir generated/swift
	cp $(CORE)/generated/swift/unfydqry.swift $(SWIFT_OUT)

verify-bindings: dylib ## Fail if committed bindings drift from the Rust signatures.
	cd $(CORE) && cargo run --bin uniffi-bindgen -- generate \
		--library $(DYLIB) --language kotlin --out-dir generated/kotlin
	diff -u $(KOTLIN_OUT) $(CORE)/generated/kotlin/uniffi/unfydqry/unfydqry.kt
	cd $(CORE) && cargo run --bin uniffi-bindgen -- generate --no-format \
		--library $(DYLIB) --language swift --out-dir generated/swift
	diff -u $(SWIFT_OUT) $(CORE)/generated/swift/unfydqry.swift

ci: check verify-bindings ## Everything the PR gates check.
