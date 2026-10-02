// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FolioCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FolioCore", targets: ["FolioCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.0.0")],
    targets: [
        .target(name: "FolioArchive", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "FolioCore", dependencies: ["FolioArchive", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
