// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VolumeKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VolumeCore", targets: ["VolumeCore"]),
        .library(name: "VolumeUI", targets: ["VolumeUI"]),
    ],
    targets: [
        .target(name: "VolumeCore"),
        .target(name: "VolumeUI", dependencies: ["VolumeCore"], resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "VolumeCoreTests", dependencies: ["VolumeCore"]),
    ]
)
