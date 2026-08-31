// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WealthWorkbench",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WealthWorkbench", targets: ["WealthWorkbench"])
    ],
    targets: [
        .executableTarget(
            name: "WealthWorkbench",
            path: "Sources/WealthWorkbench",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Network"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
