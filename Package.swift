// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PinVol",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "PinVol",
            path: "Sources/PinVol",
            swiftSettings: [.unsafeFlags(["-Ounchecked"])]
        )
    ]
)
