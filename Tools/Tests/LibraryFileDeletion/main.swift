import Foundation

let fm = FileManager.default
let sandbox = fm.temporaryDirectory.appendingPathComponent("amp-deletion-tests-\(UUID().uuidString)")
let root = sandbox.appendingPathComponent("Music")
try fm.createDirectory(at: root.appendingPathComponent("Album"), withIntermediateDirectories: true)
defer { try? fm.removeItem(at: sandbox) }
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}
func refuses(_ path: String) {
    do {
        try LibraryFileDeletion.remove(relativePath: path, in: root)
        fatalError("Deletion unexpectedly accepted: \(path)")
    } catch { checks += 1 }
}
let track = root.appendingPathComponent("Album/song.m4a")
let sibling = root.appendingPathComponent("Album/keep.m4a")
try Data([1, 2]).write(to: track)
try Data([3]).write(to: sibling)
try LibraryFileDeletion.remove(relativePath: "Album/song.m4a", in: root)
check(!fm.fileExists(atPath: track.path), "The actual song file must disappear")
check(fm.fileExists(atPath: sibling.path), "Other songs must survive")
refuses("Album/song.m4a") // Missing file must be reported, not silently claimed deleted.
refuses("")
refuses("Album")
refuses("../Music/../")
let outsideFolder = sandbox.appendingPathComponent("Music-other")
try fm.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
let outside = outsideFolder.appendingPathComponent("outside.m4a")
try Data([4]).write(to: outside)
refuses("../Music-other/outside.m4a")
try fm.createSymbolicLink(at: root.appendingPathComponent("outside-link"), withDestinationURL: outside)
refuses("outside-link")
try fm.createSymbolicLink(at: root.appendingPathComponent("inside-link"), withDestinationURL: sibling)
refuses("inside-link")
try fm.createSymbolicLink(at: root.appendingPathComponent("linked-folder"), withDestinationURL: outsideFolder)
refuses("linked-folder/outside.m4a")
check(fm.fileExists(atPath: outside.path), "Files outside amp must survive")
check(fm.fileExists(atPath: sibling.path), "Link targets must survive")
print("Passed \(checks) real file deletion checks")

let batchFirst = root.appendingPathComponent("Album/batch-a.mp3")
let batchSecond = root.appendingPathComponent("Album/batch-b.mp3")
try Data([7]).write(to: batchFirst)
try Data([8]).write(to: batchSecond)
let result = LibraryFileDeletion.remove(relativePaths: ["Album/batch-a.mp3", "Album/batch-b.mp3", "Album/batch-a.mp3", "missing.mp3", "Album", "../Music-other/outside.m4a"], in: root)
check(result.deleted == ["Album/batch-a.mp3", "Album/batch-b.mp3"], "Only selected regular files are reported deleted; duplicates are processed once")
check(result.failed == ["missing.mp3", "Album", "../Music-other/outside.m4a"], "Partial failures remain explicit")
check(!fm.fileExists(atPath: batchFirst.path) && !fm.fileExists(atPath: batchSecond.path), "Selected audio files are actually removed")
check(fm.fileExists(atPath: sibling.path) && fm.fileExists(atPath: outside.path), "Unselected and external audio survive a batch")
print("Passed \(checks) total single and batch deletion checks")
