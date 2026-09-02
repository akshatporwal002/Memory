// swift-tools-version: 5.10
import PackageDescription

var targets: [Target] = [
    .target(name: "CSQLite", exclude: ["PROVENANCE.md"], cSettings: [.define("SQLITE_THREADSAFE", to: "1"), .define("SQLITE_OMIT_LOAD_EXTENSION")]),
    .target(name: "CArchive", exclude: ["LICENSE", "PROVENANCE.md"], cSettings: [.define("MINIZ_NO_ZLIB_COMPATIBLE_NAMES")]),
    .target(name: "LearningCore"),
    .target(name: "StudyApplication", dependencies: ["LearningCore"]),
    .target(name: "PersistenceAdapters", dependencies: ["LearningCore"]),
    .target(name: "SchedulingAdapters", dependencies: ["LearningCore", .product(name: "FSRS", package: "FSRS")]),
    .target(name: "AnkiAdapters", dependencies: ["LearningCore", "CSQLite", "CArchive"]),
    .testTarget(name: "AnkiAdapterTests", dependencies: ["AnkiAdapters", "LearningCore", "SchedulingAdapters"], resources: [.copy("Fixtures")]),
    .testTarget(name: "EngramTests", dependencies: ["LearningCore", "StudyApplication", "PersistenceAdapters", "SchedulingAdapters"])
]
var products: [Product] = [
    .library(name: "AnkiAdapters", targets: ["AnkiAdapters"]),
    .library(name: "LearningCore", targets: ["LearningCore"]),
    .library(name: "StudyApplication", targets: ["StudyApplication"]),
    .library(name: "PersistenceAdapters", targets: ["PersistenceAdapters"]),
    .library(name: "SchedulingAdapters", targets: ["SchedulingAdapters"])
]
#if os(macOS)
targets += [.target(name: "DesignSystem"), .target(name: "Features", dependencies: ["LearningCore", "StudyApplication", "DesignSystem"])]
products += [.library(name: "DesignSystem", targets: ["DesignSystem"]), .library(name: "Features", targets: ["Features"])]
#endif
let package = Package(name: "Engram", platforms: [.iOS(.v17), .macOS(.v14)], products: products,
    dependencies: [.package(path: "Vendor/FSRS")], targets: targets)
