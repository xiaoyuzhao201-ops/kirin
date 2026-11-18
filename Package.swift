// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexContextLauncher",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexContextLauncher", targets: ["CodexContextLauncher"])],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "CodexContextLauncher", dependencies: ["LauncherCore"]),
        .executableTarget(name: "LauncherChecks", dependencies: ["LauncherCore"], path: "Tests/LauncherChecks"),
    ]
)
