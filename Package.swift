// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenPixel",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenPixel", targets: ["OpenPixel"])],
    targets: [
        .executableTarget(
            name: "OpenPixel",
            path: "App",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    ]
)

