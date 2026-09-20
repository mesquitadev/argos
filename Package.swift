// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Argos",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Argos",
            path: "Sources/Argos",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // O SwiftPM não liga AVKit sozinho: sem isto o app compila e morre
            // ao abrir, reclamando que não consegue resolver AVPlayerView.
            linkerSettings: [
                .linkedFramework("AVKit"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
