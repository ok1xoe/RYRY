// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mmtty4mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WaveFile", targets: ["WaveFile"]),
        .library(name: "ModemKit", targets: ["ModemKit"]),
        .library(name: "RTTYModem", targets: ["RTTYModem"]),
        .executable(name: "rtty-tool", targets: ["rtty-tool"]),
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
                              "-Wno-parentheses", "-Wno-dangling-else", "-Wno-unused-variable",
                              "-Wno-nontrivial-memcall"]),
            ]
        ),
        .testTarget(name: "MMTTYCoreTests", dependencies: ["MMTTYCore", "RTTYSignalKit", "WaveFile"],
                    resources: [.copy("Fixtures")]),
        .target(name: "ModemKit"),
        .testTarget(name: "ModemKitTests", dependencies: ["ModemKit"]),
        .target(name: "RTTYModem", dependencies: ["MMTTYCore", "ModemKit"]),
        .testTarget(name: "RTTYModemTests", dependencies: ["RTTYModem", "ModemKit", "RTTYSignalKit"]),
        .executableTarget(name: "rtty-tool", dependencies: ["RTTYModem", "ModemKit", "WaveFile", "RTTYSignalKit"]),
        .target(name: "RTTYSignalKit"),
        .testTarget(name: "RTTYSignalKitTests", dependencies: ["RTTYSignalKit"]),
    ],
    cxxLanguageStandard: .cxx17
)
