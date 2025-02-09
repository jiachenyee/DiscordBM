// swift-tools-version: 5.6

import PackageDescription

#if swift(>=5.7)
let swiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-Xfrontend", "-strict-concurrency=targeted"])
]
#else
let swiftSettings: [SwiftSetting] = []
#endif

let package = Package(
    name: "DiscordBM",
    platforms: [
        .macOS(.v12),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "DiscordBM",
            targets: ["DiscordBM"]
        ),
        .library(
            name: "DiscordLogger",
            targets: ["DiscordLogger"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.42.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.2"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.6.4"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor/multipart-kit.git", from: "4.5.2"),
        /// `WebSocketKit` dependencies
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.14.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.11.4"),
    ],
    targets: [
        .target(
            name: "DiscordBM",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "MultipartKit", package: "multipart-kit"),
                "DiscordAuth",
                "DiscordHTTP",
                "DiscordCore",
                "DiscordGateway",
                "DiscordLogger",
                "DiscordModels",
                "DiscordUtilities",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiscordHTTP",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                "DiscordModels",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiscordCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MultipartKit", package: "multipart-kit"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiscordGateway",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                "WebSocketKitFork",
                "DiscordHTTP",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiscordLogger",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                "DiscordHTTP",
                "DiscordUtilities",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DiscordModels",
            dependencies: [
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "MultipartKit", package: "multipart-kit"),
                "DiscordCore"
            ],
            swiftSettings: swiftSettings
        ),
        .target(name: "DiscordUtilities"),
        .target(
            name: "DiscordAuth",
            dependencies: [
                "DiscordModels"
            ],
            swiftSettings: swiftSettings
        ),
        /// `WebSocketKit` will be replaced as soon as changes are final and merged in
        /// Vapor's `WebSocketKit`. This is just a copy-paste of that library.
        .target(name: "WebSocketKitFork", dependencies: [
            "CZlib",
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            .product(name: "NIOFoundationCompat", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOSSL", package: "swift-nio-ssl"),
            .product(name: "NIOWebSocket", package: "swift-nio"),
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            .product(name: "Atomics", package: "swift-atomics")
        ]),
        /// `WebSocketKit` dependency
        .target(
            name: "CZlib",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: "DiscordBMTests",
            dependencies: ["DiscordBM"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["DiscordBM"]
        ),
    ]
)
