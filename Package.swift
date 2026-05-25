// swift-tools-version:6.0
import PackageDescription

// クロスプラットフォーム検索エンジン(Rust + UniFFI)の Swift パッケージ。
// Package.swift はリポジトリのルートに置きつつ、iOS 関係のソース・テスト・
// XCFramework は ios/ 配下にまとめている。
//
// `binaryTarget` で XCFramework を取り込み、`SearchCoreFFI` の C モジュールが
// XCFramework 内の modulemap 経由で公開される(中身は libsearch_core.a)。
// 利用者は `import SearchCore` だけで `SearchEngine` / `Hit` / `SearchError` /
// `normalizeLoose` に触れる。
//
// 注意:
// - XCFramework は monorepo 内で生成する成果物。core/ から再生成可能。
// - `ios/Sources/SearchCore/SearchCore.swift` は uniffi-bindgen により Rust から
//   生成されたバインディング。手で書き換えない。
let package = Package(
    name: "SearchCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SearchCore", targets: ["SearchCore"])
    ],
    targets: [
        .binaryTarget(
            name: "SearchCoreFFI",
            path: "ios/SearchCore.xcframework"
        ),
        .target(
            name: "SearchCore",
            dependencies: ["SearchCoreFFI"],
            path: "ios/Sources/SearchCore"
        ),
        .testTarget(
            name: "SearchCoreTests",
            dependencies: ["SearchCore"],
            path: "ios/Tests/SearchCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
