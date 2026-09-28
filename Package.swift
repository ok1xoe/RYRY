// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mmtty4mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WaveFile", targets: ["WaveFile"]),
    ],
    targets: [
        .target(name: "WaveFile"),
        .testTarget(name: "WaveFileTests", dependencies: ["WaveFile"]),
        .target(
            name: "MMTTYCore",
            path: "Sources/MMTTYCore",
            cxxSettings: [
                .headerSearchPath("mmtty"),
                .headerSearchPath("compat"),
                .unsafeFlags(["-Wno-deprecated-declarations", "-Wno-writable-strings",
                              "-Wno-parentheses", "-Wno-dangling-else", "-Wno-unused-variable"]),
            ]
        ),
        .testTarget(name: "MMTTYCoreTests", dependencies: ["MMTTYCore", "RTTYSignalKit", "WaveFile"],
                    resources: [.copy("Fixtures")]),
        .target(name: "RTTYSignalKit"),
        .testTarget(name: "RTTYSignalKitTests", dependencies: ["RTTYSignalKit"]),
    ],
    cxxLanguageStandard: .cxx17
)
