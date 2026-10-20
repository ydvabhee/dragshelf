// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "DragShelf",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DragShelf", swiftSettings: settings),
        .testTarget(name: "DragShelfTests", dependencies: ["DragShelf"], swiftSettings: settings),
    ]
)
