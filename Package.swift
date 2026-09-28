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
    ],
    cxxLanguageStandard: .cxx17
)
