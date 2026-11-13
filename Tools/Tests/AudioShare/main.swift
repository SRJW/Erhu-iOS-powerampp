import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let source = root.appendingPathComponent("Song.m4a")
let bytes = Data([0, 1, 2, 3, 255])
try bytes.write(to: source)
precondition(PreparedAudioShare.available(source))
precondition(!PreparedAudioShare.available(root))
precondition(!PreparedAudioShare.available(URL(string: "https://example.com/song.m4a")!))
let first = try PreparedAudioShare.prepare(source)
let second = try PreparedAudioShare.prepare(source)
precondition(first.url != source && first.url != second.url)
precondition(first.url.lastPathComponent == source.lastPathComponent)
let copied = try Data(contentsOf: first.url)
precondition(copied == bytes)
first.remove()
precondition(!FileManager.default.fileExists(atPath: first.directory.path))
precondition(FileManager.default.fileExists(atPath: second.url.path))
let original = try Data(contentsOf: source)
precondition(original == bytes)
second.remove()
try FileManager.default.removeItem(at: source)
precondition(!PreparedAudioShare.available(source))
do {
    _ = try PreparedAudioShare.prepare(source)
    fatalError("Missing audio must not be shared")
} catch { print("Passed audio sharing: real file copy, unique temporary files, cleanup, original preservation and missing file checks") }
