import Foundation

/// Canonical location for app-managed state (token, history, settings).
///
/// On first launch, contents of the upstream `~/.config/claude-usage-bar/`
/// directory are copied into the new location and left in place so the user
/// can clean them up manually.
enum AppSupport {
    static let directoryName = "ParamClaudeBar"
    static let legacyDirectoryRelativePath = ".config/claude-usage-bar"

    static var directoryURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    static var legacyDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(legacyDirectoryRelativePath, isDirectory: true)
    }

    /// Ensure the app-support directory exists with private permissions and
    /// run the one-shot legacy migration. Safe to call repeatedly.
    @discardableResult
    static func ensureDirectory(fileManager: FileManager = .default) -> URL {
        _ = legacyMigration
        let url = directoryURL
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static let legacyMigration: Void = {
        performLegacyMigrationIfNeeded()
    }()

    static func performLegacyMigrationIfNeeded(fileManager: FileManager = .default) {
        let legacy = legacyDirectoryURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: legacy.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }

        let destination = directoryURL
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)

        guard let entries = try? fileManager.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for source in entries {
            let target = destination.appendingPathComponent(source.lastPathComponent)
            guard fileManager.fileExists(atPath: target.path) == false else { continue }
            try? fileManager.copyItem(at: source, to: target)
        }
    }
}
