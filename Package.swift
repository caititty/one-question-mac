// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OneQuestion",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OneQuestion", targets: ["OneQuestionMac"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "OneQuestionCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "OneQuestionMac", dependencies: ["OneQuestionCore"],
                          linkerSettings: [.linkedFramework("Security")]),
        .testTarget(name: "OneQuestionCoreTests", dependencies: ["OneQuestionCore"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
