// swift-tools-version:6.0
import PackageDescription

// クロスプラットフォーム検索エンジン(Rust + UniFFI)の Swift パッケージ。
// Rust 側のクレート名は `unq`、Swift 側のパッケージ名は `UniversalQuery` を採用する。
// Package.swift はリポジトリのルートに置きつつ、iOS 関係のソース・テスト・
// XCFramework は ios/ 配下にまとめている。
//
// `binaryTarget` で XCFramework を取り込み、`unqFFI` の C モジュールが
// XCFramework 内の modulemap 経由で公開される(中身は libunq.a)。
// 利用者は `import UniversalQuery` だけで `SearchEngine` / `Hit` / `SearchError` /
// `normalizeLoose` に触れる。
//
// 注意:
// - XCFramework は monorepo 内で生成する成果物。core/ から再生成可能。
// - `ios/Sources/UniversalQuery/UniversalQuery.swift` は uniffi-bindgen により
//   Rust から生成されたバインディング。手で書き換えない。
let package = Package(
    name: "UniversalQuery",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "UniversalQuery", targets: ["UniversalQuery"])
    ],
    targets: [
        .binaryTarget(
            name: "unqFFI",
            path: "ios/UniversalQuery.xcframework"
        ),
        .target(
            name: "UniversalQuery",
            dependencies: ["unqFFI"],
            path: "ios/Sources/UniversalQuery"
        ),
        .testTarget(
            name: "UniversalQueryTests",
            dependencies: ["UniversalQuery"],
            path: "ios/Tests/UniversalQueryTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
