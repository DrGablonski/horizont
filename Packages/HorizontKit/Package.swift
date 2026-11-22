// swift-tools-version: 5.9
// HorizontKit: geteilte Basis (API-Modelle, HTTP-Client, Keychain) für
// apple/ (macOS), ipad/ (iPadOS) und iphone/ (iOS). Deployment-Ziele
// entsprechen den Werten in den jeweiligen project.yml Dateien.
import PackageDescription

let package = Package(
    name: "HorizontKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "HorizontKit", targets: ["HorizontKit"])
    ],
    targets: [
        .target(name: "HorizontKit")
    ]
)
