import Foundation
import OSLog
import UIKit

/// Observe SwiftUI's scenes without replacing their delegates or changing activation.
@MainActor
final class AppLifecycleDiagnostics: NSObject, UIApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        LifecycleLog.record("app.launch bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "nil") executable=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "nil")")
        for (name, event) in [
            (UIScene.willEnterForegroundNotification, "sceneWillEnterForeground"),
            (UIScene.didActivateNotification, "sceneDidBecomeActive"),
            (UIScene.didEnterBackgroundNotification, "sceneDidEnterBackground"),
            (UIScene.willDeactivateNotification, "sceneWillResignActive")
        ] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated {
                    guard let scene = note.object as? UIScene else { return }
                    LifecycleLog.record("\(event) source=UIScene.notification scene=\(scene.session.persistentIdentifier) activationState=\(scene.activationState.rawValue)")
                }
            })
        }
        return true
    }
}

/// Release-build diagnostics readable in Files, including while the phone is locked.
enum LifecycleLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "amp", category: "AppLifecycle")
    private static let queue = DispatchQueue(label: "amp.lifecycle-log", qos: .utility)
    private static let session = UUID().uuidString
    private static let maximumBytes = 1_048_576
    private static let folder = URL.documentsDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
    private static let file = folder.appendingPathComponent("lifecycle.log")
    private static let previous = folder.appendingPathComponent("lifecycle.previous.log")
    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    static func record(_ event: String) {
        let date = Date()
        queue.async {
            let line = "\(timestamp.string(from: date)) session=\(session) pid=\(ProcessInfo.processInfo.processIdentifier) \(event)"
            logger.notice("\(line, privacy: .public)")
            do {
                let manager = FileManager.default
                try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                var directory = folder
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                if manager.fileExists(atPath: file.path),
                   let size = try manager.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
                   size.intValue >= maximumBytes {
                    if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                    try manager.moveItem(at: file, to: previous)
                }
                if !manager.fileExists(atPath: file.path) {
                    guard manager.createFile(atPath: file.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } catch {
                logger.error("Lifecycle file write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
