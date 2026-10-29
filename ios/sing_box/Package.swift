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
// These `let libbox... = "..."` lines are the single source of truth for the
// iOS libbox binary: `ios/libbox.rb` (CocoaPods) parses them, and the release
// script rewrites them. Keep the `let name = "value"` format. The `Lx` pair is
// the sing-box-lx core.
let libboxVersion = "1.14.4"
let libboxChecksum = "8bca7d8f5f8615df5d719a0e50fd2364d041cd2182ebda2d981d1e7494c71c40"
let libboxLxVersion = "1.14.4-lx.25"
let libboxLxChecksum = "6839dc8e1f7e5d98f10a8e5000c63145f5cbdd005a1099f5af20b520134cf345"
let libboxBaseURL = "https://github.com/QUSAD-prod/sing_box/releases/download"

// The core to link: `SING_BOX_CORE=lx` in the environment of the build
// (`flutter build ios`, `xcodebuild`, or Xcode started from such a shell)
// links sing-box-lx. SwiftPM resolves the plugin's symlink in the app, so this
// manifest cannot read the app's pubspec.yaml (CocoaPods builds can).
let core = Context.environment["SING_BOX_CORE"] == "lx" ? "lx" : "standard"
let isLx = core == "lx"

// Local development: `scripts/build_libbox.sh apple --install` puts the
// framework here (git-ignored; lx: `Frameworks/lx/`), which takes precedence
// over the download.
let localLibboxPath = isLx ? "Frameworks/lx/Libbox.xcframework" : "Frameworks/Libbox.xcframework"
let hasLocalLibbox = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/" + localLibboxPath + "/Info.plist"
)

let libboxTarget: Target = hasLocalLibbox
    ? .binaryTarget(name: "Libbox", path: localLibboxPath)
    : .binaryTarget(
        name: "Libbox",
        url: "\(libboxBaseURL)/libbox-v\(isLx ? libboxLxVersion : libboxVersion)/Libbox.xcframework.zip",
        checksum: isLx ? libboxLxChecksum : libboxChecksum
    )

// Members of libbox protocols that differ between the cores live in
// Sources/sing_box/Core/<core>.
let otherCoreSources = isLx ? "Core/standard" : "Core/lx"

// Go's runtime in libbox needs libresolv; libbox also uses UIDevice, and a
// Network Extension target does not link UIKit by itself.
let libboxLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("resolv"),
    .linkedFramework("UIKit"),
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
            exclude: [otherCoreSources],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            linkerSettings: libboxLinkerSettings
        ),
    ]
)
