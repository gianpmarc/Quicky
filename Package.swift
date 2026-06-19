// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Quicky",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Quicky", targets: ["Quicky"])
    ],
    targets: [
        .executableTarget(name: "Quicky")
    ]
)
