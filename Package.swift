// swift-tools-version: 5.10
import PackageDescription

var targets: [Target] = [
    .target(name: "ChatGPTAuth"),
    .testTarget(name: "ChatGPTAuthTests", dependencies: ["ChatGPTAuth"]),
    .target(name: "CSQLite", exclude: ["PROVENANCE.md"], cSettings: [.define("SQLITE_THREADSAFE", to: "1"), .define("SQLITE_OMIT_LOAD_EXTENSION")]),
    .target(name: "CArchive", exclude: ["LICENSE", "PROVENANCE.md"], cSettings: [.define("MINIZ_NO_ZLIB_COMPATIBLE_NAMES")]),
    .target(name: "LearningCore"),
    .target(name: "StudyApplication", dependencies: ["LearningCore"]),
    .target(name: "PersistenceAdapters", dependencies: ["LearningCore"]),
    .target(name: "SchedulingAdapters", dependencies: ["LearningCore", .product(name: "FSRS", package: "FSRS")]),
    .target(name: "AnkiAdapters", dependencies: ["LearningCore", "CSQLite", "CArchive"]),
    .executableTarget(name: "EngramBenchmark", dependencies: ["LearningCore", "StudyApplication", "PersistenceAdapters", "SchedulingAdapters", "AnkiAdapters"], path: "Tools/EngramBenchmark"),
    .testTarget(name: "AnkiAdapterTests", dependencies: ["AnkiAdapters", "LearningCore", "SchedulingAdapters"], resources: [.copy("Fixtures")]),
    .testTarget(name: "EngramTests", dependencies: ["Features", "LearningCore", "StudyApplication", "PersistenceAdapters", "SchedulingAdapters", "AnkiAdapters"])
]
var products: [Product] = [
    .library(name: "ChatGPTAuth", targets: ["ChatGPTAuth"]),
    .executable(name: "EngramBenchmark", targets: ["EngramBenchmark"]),
    .library(name: "AnkiAdapters", targets: ["AnkiAdapters"]),
    .library(name: "LearningCore", targets: ["LearningCore"]),
    .library(name: "StudyApplication", targets: ["StudyApplication"]),
    .library(name: "PersistenceAdapters", targets: ["PersistenceAdapters"]),
    .library(name: "SchedulingAdapters", targets: ["SchedulingAdapters"])
]
targets += [.target(name: "DesignSystem"), .target(name: "Features", dependencies: ["LearningCore", "StudyApplication", "DesignSystem", "ChatGPTAuth", .product(name: "FluidAudio", package: "FluidAudio")], resources: [.process("Resources")])]
products += [.library(name: "DesignSystem", targets: ["DesignSystem"]), .library(name: "Features", targets: ["Features"])]
let package = Package(name: "Engram", platforms: [.iOS(.v17), .macOS(.v14)], products: products,
    dependencies: [.package(path: "Vendor/FSRS"), .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "8145085136df11758cc1303ab54d8e032c12bd41")], targets: targets)
