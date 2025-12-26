import Foundation

public enum FilePath {
    // Bundle ID for Flutter plugin - needs to be configured for your app
    public static let packageName = "com.qusadprod.sing_box"
}

public extension FilePath {
    static let groupName = "group.\(packageName)"
    
    private static let defaultSharedDirectory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)
    
    #if os(iOS)
        static var sharedDirectory: URL {
            guard let directory = defaultSharedDirectory else {
                // Fallback to standard directory if App Groups not configured
                guard let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    // Last fallback - temporary directory
                    let tempDir = FileManager.default.temporaryDirectory
                    NSLog("FilePath: App Groups not configured and documentDirectory unavailable, using temp: \(tempDir.path)")
                    return tempDir
                }
                NSLog("FilePath: App Groups not configured, using fallback directory: \(fallback.path)")
                return fallback
            }
            return directory
        }
    #elseif os(tvOS)
        static var sharedDirectory: URL {
            guard let directory = defaultSharedDirectory else {
                guard let fallback = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                    let tempDir = FileManager.default.temporaryDirectory
                    NSLog("FilePath: App Groups not configured and cachesDirectory unavailable, using temp: \(tempDir.path)")
                    return tempDir
                }
                NSLog("FilePath: App Groups not configured, using fallback directory: \(fallback.path)")
                return fallback
            }
            return directory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }
    #elseif os(macOS)
        static var sharedDirectory: URL {
            guard let directory = defaultSharedDirectory else {
                guard let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    let tempDir = FileManager.default.temporaryDirectory
                    NSLog("FilePath: App Groups not configured and applicationSupportDirectory unavailable, using temp: \(tempDir.path)")
                    return tempDir
                }
                NSLog("FilePath: App Groups not configured, using fallback directory: \(fallback.path)")
                return fallback
            }
            return directory
        }
    #endif
    
    #if os(iOS)
        static let cacheDirectory = sharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    #elseif os(tvOS)
        static let cacheDirectory = sharedDirectory
    #elseif os(macOS)
        static var cacheDirectory: URL {
            sharedDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }
    #endif
    
    #if os(macOS)
        static var workingDirectory: URL {
            cacheDirectory.appendingPathComponent("Working", isDirectory: true)
        }
    #else
        static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)
    #endif
    
    static var iCloudDirectory = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true) ?? URL(string: "stub")!
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
    
    var relativePath: String {
        path
    }
}

