// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ITools",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "ITools", targets: ["ITools"])],
    targets: [
        .target(name: "SystemBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "IToolsCore"),
        .executableTarget(name: "ITools", dependencies: ["IToolsCore", "SystemBridge"], linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("AVFoundation"), .linkedFramework("Vision"),
            .linkedFramework("Carbon"), .linkedFramework("IOKit"), .linkedFramework("QuartzCore")
        ]),
        .testTarget(name: "IToolsCoreTests", dependencies: ["IToolsCore", "SystemBridge"])
    ]
)
