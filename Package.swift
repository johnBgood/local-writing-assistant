// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LocalWriter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalWriter", targets: ["LocalWriter"])],
    targets: [
        .target(name: "WritingCore"),
        .executableTarget(name: "LocalWriter", dependencies: ["WritingCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["WritingCore"], path: "Tests/WritingCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
