// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "FenixuzCore",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "FenixuzCore", targets: ["FenixuzCore"]),
    ],
    dependencies: [
        .package(name: "TGUIKit",      path: "../TGUIKit"),
        .package(name: "Localization", path: "../Localization"),
    ],
    targets: [
        .target(
            name: "FenixuzCore",
            dependencies: [
                .product(name: "TGUIKit",      package: "TGUIKit"),
                .product(name: "Localization", package: "Localization"),
            ],
            path: "Sources/FenixuzCore"
        ),
    ]
)
