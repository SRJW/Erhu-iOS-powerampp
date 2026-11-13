import Foundation

/// Share a private copy, so cancellation and receivers cannot modify the original audio file.
struct PreparedAudioShare: Identifiable, Sendable {
    let id = UUID()
    let directory: URL
    let url: URL

    static func available(_ source: URL) -> Bool {
        guard source.isFileURL else { return false }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: source.path, isDirectory: &directory) && !directory.boolValue
    }

    static func prepare(_ source: URL) throws -> Self {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amp-share-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            return Self(directory: directory, url: destination)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

