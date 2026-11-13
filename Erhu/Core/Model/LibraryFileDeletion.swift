import Foundation

/// Deletes only regular files owned by the app's Files-visible music folder.
enum LibraryFileDeletion {
    struct BatchResult {
        let deleted: Set<String>
        let failed: Set<String>
    }

    /// Each file retains the same ownership checks. One failure never claims another file succeeded.
    static func remove(relativePaths: [String], in folder: URL) -> BatchResult {
        var deleted = Set<String>(), failed = Set<String>(), visited = Set<String>()
        for path in relativePaths where visited.insert(path).inserted {
            do { try remove(relativePath: path, in: folder); deleted.insert(path) }
            catch { failed.insert(path) }
        }
        return BatchResult(deleted: deleted, failed: failed)
    }

    static func remove(relativePath: String, in folder: URL) throws {
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appendingPathComponent(relativePath).standardizedFileURL
        let resolved = file.resolvingSymlinksInPath()
        guard !relativePath.isEmpty, resolved.path.hasPrefix(root.path + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        // Refuse directories and links, including links to another location in the library.
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: file)
    }
}
