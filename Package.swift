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
        .executableTarget(name: "rtty-tool", dependencies: ["RTTYModem", "ModemKit", "WaveFile", "RTTYSignalKit",
                                                          "Engine", "AudioIO", "Keying", "RigControl"]),
        .target(name: "XMLRPC"),
        .testTarget(name: "XMLRPCTests", dependencies: ["XMLRPC"]),
        .target(name: "RigControl", dependencies: ["XMLRPC"]),
        .testTarget(name: "RigControlTests", dependencies: ["RigControl", "XMLRPC"]),
        .target(name: "CSerial"),
        .target(name: "Keying", dependencies: ["CSerial", "RigControl"]),
        .target(name: "TestSupport", dependencies: ["Keying", "AudioIO"]),
        .target(name: "Engine", dependencies: ["ModemKit", "AudioIO", "Keying", "RigControl"]),
        .testTarget(name: "EngineTests", dependencies: ["Engine", "RTTYModem", "RTTYSignalKit", "TestSupport",
                                                        "AudioIO", "Keying", "ModemKit", "RigControl"]),
        .testTarget(name: "KeyingTests", dependencies: ["Keying", "RigControl", "TestSupport"]),
        .target(name: "CRingBuffer"),
        .target(name: "AudioIO", dependencies: ["CRingBuffer"]),
        .testTarget(name: "AudioIOTests", dependencies: ["AudioIO"]),
        .target(name: "QSOLog"),
        .testTarget(name: "QSOLogTests", dependencies: ["QSOLog"]),
        .target(name: "MacroEngine"),
        .testTarget(name: "MacroEngineTests", dependencies: ["MacroEngine"]),
        .target(name: "RTTYSignalKit"),
        .testTarget(name: "RTTYSignalKitTests", dependencies: ["RTTYSignalKit"]),
    ],
    cxxLanguageStandard: .cxx17
)
