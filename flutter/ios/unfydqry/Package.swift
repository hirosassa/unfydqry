// swift-tools-version: 5.9
// Swift Package Manager manifest for the iOS side of the unfydqry Flutter plugin.
//
// The package is self-contained: it vendors the Rust core's FFI XCFramework
// (`unfydqryFFI`) and compiles the generated UniFFI Swift binding
// (UnifiedQueryBinding.swift) straight into the plugin module, alongside
// UnfydqryPlugin.swift. So `SearchEngine`, `NormalizeOptions`, etc. live in
// this module — no separate `import` is needed.
//
// Why self-contained instead of depending on the repo's UnifiedQuery package:
// Flutter integrates plugin Swift packages by *symlinking* them into the app's
// ephemeral build dir, and SwiftPM resolves a path dependency relative to that
// symlink — so a `path:` dependency that escapes the plugin directory cannot
// be resolved. Vendoring keeps every path inside the package.
//
// Both vendored artifacts are gitignored build inputs, refreshed from the
// canonical sources under <repo>/ios by the build step documented in
// docs/flutter-plugin.md:
//   ios/UnifiedQuery.xcframework            -> ios/unfydqry/UnifiedQuery.xcframework
//   ios/Sources/UnifiedQuery/UnifiedQuery.swift -> ios/unfydqry/Sources/unfydqry/UnifiedQueryBinding.swift
//
// `FlutterFramework` is provided by the Flutter tool at build time and supplies
// the `Flutter` module.
import PackageDescription

let package = Package(
    name: "unfydqry",
    // The Rust core's Swift binding targets iOS 18; the consuming app must
    // deploy to >= 18.
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .library(name: "unfydqry", targets: ["unfydqry"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "unfydqryFFI",
            path: "UnifiedQuery.xcframework"
        ),
        .target(
            name: "unfydqry",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "unfydqryFFI"
            ]
        )
    ]
)
