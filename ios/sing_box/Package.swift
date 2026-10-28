// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// MARK: - libbox (sing-box core) binary
//
// The ~200 MB `Libbox.xcframework` is not part of the pub package. It is
// downloaded from the GitHub release below and verified with `libboxChecksum`
// (`swift package compute-checksum Libbox.xcframework.zip`).
//
// These three `let libbox... = "..."` lines are the single source of truth for
// the iOS libbox binary: `ios/libbox.rb` (CocoaPods) parses them, and the
// release script rewrites them. Keep the `let name = "value"` format.
let libboxVersion = "1.14.4"
let libboxChecksum = "8bca7d8f5f8615df5d719a0e50fd2364d041cd2182ebda2d981d1e7494c71c40"
let libboxBaseURL = "https://github.com/QUSAD-prod/sing_box/releases/download"

// Local development: `scripts/build_libbox.sh apple --install` puts the
// framework here (git-ignored), which takes precedence over the download.
let localLibboxPath = "Frameworks/Libbox.xcframework"
let hasLocalLibbox = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/" + localLibboxPath + "/Info.plist"
)

let libboxTarget: Target = hasLocalLibbox
    ? .binaryTarget(name: "Libbox", path: localLibboxPath)
    : .binaryTarget(
        name: "Libbox",
        url: "\(libboxBaseURL)/libbox-v\(libboxVersion)/Libbox.xcframework.zip",
        checksum: libboxChecksum
    )

// Go's runtime in libbox needs libresolv.
let libboxLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("resolv"),
]

// Recent Flutter versions generate a FlutterFramework package next to this
// one in ios/Flutter/ephemeral/Packages/.packages/ and expect plugins to depend
// on it. Older versions (Swift Package Manager was opt-in before Flutter 3.44)
// do not generate it and provide the Flutter module themselves.
let hasFlutterFramework = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/../FlutterFramework/Package.swift"
)
let flutterPackages: [Package.Dependency] = hasFlutterFramework
    ? [.package(name: "FlutterFramework", path: "../FlutterFramework")]
    : []
let flutterProducts: [Target.Dependency] = hasFlutterFramework
    ? [.product(name: "FlutterFramework", package: "FlutterFramework")]
    : []

let package = Package(
    name: "sing_box",
    platforms: [
        .iOS("15.0"),
    ],
    products: [
        // The Flutter plugin (linked into the app by Flutter's generated package).
        .library(name: "sing-box", targets: ["sing_box"]),
        // The Packet Tunnel provider for the host app's Network Extension target.
        // It has no Flutter dependency.
        .library(name: "SingBoxTunnel", targets: ["SingBoxTunnel"]),
    ],
    dependencies: flutterPackages,
    targets: [
        libboxTarget,
        // Code shared by the app (plugin) and the extension: app group
        // resolution, file locations, keys, libbox helpers.
        .target(
            name: "SingBoxShared",
            dependencies: ["Libbox"],
            linkerSettings: libboxLinkerSettings
        ),
        .target(
            name: "SingBoxTunnel",
            dependencies: ["SingBoxShared", "Libbox"],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            linkerSettings: libboxLinkerSettings
        ),
        .target(
            name: "sing_box",
            dependencies: flutterProducts + [
                "SingBoxShared",
                "Libbox",
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            linkerSettings: libboxLinkerSettings
        ),
    ]
)
