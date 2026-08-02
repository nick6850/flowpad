// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Flowpad",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Flowpad", targets: ["FlowpadApp"])
    ],
    targets: [
        .executableTarget(
            name: "FlowpadApp",
            path: "Sources/FlowpadApp"
        )
    ]
)
