import AVFoundation
import XCTest
@testable import Erhu

final class AudioEngineTests: XCTestCase {
    /// Production playback/preview activates its requested route before opening the I/O node.
    @MainActor
    private func readyEngine() async throws -> AudioEngine {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        let engine = AudioEngine()
        await engine.setUp()
        return engine
    }

    @MainActor
    func testIdleEngineControlsDoNotImplicitlyOpenAudioOutput() {
        let engine = AudioEngine()
        engine.pause()
        engine.stopAll()
        engine.cancelCrossfade()
        XCTAssertFalse(engine.isReady)
        XCTAssertNil(engine.outputFormat)
        XCTAssertEqual(engine.outputSampleRate, 0)
        XCTAssertThrowsError(try engine.resume()) { error in
            guard case AudioEngine.EngineError.notReady = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    @MainActor
    func testRestoringThePlayerDoesNotPrepareAnAudioOutputForBrowsing() async throws {
        let database = try LibraryDatabase.inMemory()
        let controller = PlayerController(database: database, transitions: TransitionSettingsStore())
        for _ in 0..<200 {
            if controller.restoreFinished { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(controller.restoreFinished)
        XCTAssertFalse(controller.engine.isReady)
        XCTAssertNil(controller.engine.outputFormat)
    }

    @MainActor
    func testPausedAlternatingFormatsReuseTheirDecksAndResumeTheSelectedTrack() async throws {
        let urls = (0..<2).map { _ in FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf") }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        for (index, rate) in [44_100.0, 48_000.0].enumerated() {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate)))
            buffer.frameLength = buffer.frameCapacity
            for channel in 0..<2 {
                for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![channel][frame] = 0.1 }
            }
            let file = try AVAudioFile(forWriting: urls[index], settings: format.settings)
            try file.write(from: buffer)
        }
        let engine = try await readyEngine()
        defer { engine.stopAll() }
        await engine.warmFiles(urls)
        let first = UUID(), second = UUID()
        try engine.play(entryId: first, url: urls[0], positionMs: 0, startPlaying: false)
        let firstDeck = engine.active
        try engine.play(entryId: second, url: urls[1], positionMs: 0, startPlaying: false)
        let secondDeck = engine.active
        XCTAssertFalse(firstDeck === secondDeck)
        XCTAssertEqual(firstDeck.format?.sampleRate, 44_100)
        XCTAssertEqual(secondDeck.format?.sampleRate, 48_000)
        try engine.play(entryId: first, url: urls[0], positionMs: 100, startPlaying: false)
        XCTAssertTrue(engine.active === firstDeck, "Swiping back must reuse the previous graph connection")
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.currentPosition()?.entryId, first)
        XCTAssertEqual(engine.currentPosition()?.positionMs, 100)
        try engine.resume()
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.currentPosition()?.entryId, first)
    }

    @MainActor
    func testPairPreviewSchedulesOnlyTheRealCueWindowsAndStopsBothDecks() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let incomingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: incomingURL)
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132_300)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![channel][frame] = 0 }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let incomingFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let incomingBuffer = AVAudioPCMBuffer(pcmFormat: incomingFormat, frameCapacity: 144_000)!
        incomingBuffer.frameLength = incomingBuffer.frameCapacity
        for frame in 0..<Int(incomingBuffer.frameLength) { incomingBuffer.floatChannelData![0][frame] = 0 }
        do {
            let file = try AVAudioFile(forWriting: incomingURL, settings: incomingFormat.settings)
            try file.write(from: incomingBuffer)
        }
        var spec = TransitionSpec.preset(.bassSwap)
        spec.durationMs = 500
        spec.outgoingCutMs = 500
        spec.incomingStartMs = 500
        let timing = try XCTUnwrap(PairTransitionTiming(spec: spec, outgoingMs: 3000, incomingMs: 3000))
        let engine = try await readyEngine()
        defer { engine.stopAll() }
        try engine.previewTransition(outgoing: url, incoming: incomingURL, timing: timing)
        let out = try XCTUnwrap(engine.other.segments.first)
        let inc = try XCTUnwrap(engine.active.segments.first)
        XCTAssertEqual(out.fileStartFrame, 22_050)
        XCTAssertEqual(out.frameCount, 88_200)
        XCTAssertEqual(inc.fileStartFrame, 24_000)
        XCTAssertEqual(inc.frameCount, 96_000)
        XCTAssertTrue(engine.isRunning)
        var rendered: Double?
        for _ in 0..<40 {
            rendered = engine.previewPositionMs()
            if rendered != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let position = try XCTUnwrap(rendered, "The preview playhead must expose the actual render clock")
        XCTAssertGreaterThanOrEqual(position, -Double(timing.leadMs))
        XCTAssertLessThanOrEqual(position, Double(timing.plan.durationMs) + Double(timing.tailMs))
        // The overlay must receive changing render samples, not merely an initial position.
        var later = position
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if let next = engine.previewPositionMs() { later = next }
            if later > position + 100 { break }
        }
        XCTAssertGreaterThan(later, position + 100)
        engine.stopAll()
        XCTAssertNil(engine.previewPositionMs())
        XCTAssertFalse(engine.isRunning)
        XCTAssertTrue(engine.active.segments.isEmpty)
        XCTAssertTrue(engine.other.segments.isEmpty)

        let cut = try XCTUnwrap(PairTransitionTiming(spec: nil, outgoingMs: 3000, incomingMs: 3000))
        try engine.previewTransition(outgoing: url, incoming: incomingURL, timing: cut)
        XCTAssertFalse(engine.other.stage.isEngaged)
        XCTAssertFalse(engine.active.stage.isEngaged)
        XCTAssertEqual(try XCTUnwrap(engine.other.segments.first).fileStartFrame, 66_150)
        XCTAssertEqual(try XCTUnwrap(engine.other.segments.first).frameCount, 66_150)
        XCTAssertEqual(try XCTUnwrap(engine.active.segments.first).fileStartFrame, 0)
        XCTAssertEqual(try XCTUnwrap(engine.active.segments.first).frameCount, 72_000)
    }

    @MainActor
    func testManualTrackSwitchPreparesTheOtherDeckBeforeReleasingAudio() async throws {
        try await verifyManualSwitch(duration: nil)
    }

    @MainActor
    func testConfiguredManualCrossfadeKeepsTheOutgoingDeckForItsDuration() async throws {
        try await verifyManualSwitch(duration: 700)
    }

    @MainActor
    private func verifyManualSwitch(duration: Int?) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132_300)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![channel][frame] = 0.1 }
        }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let engine = try await readyEngine()
        defer { engine.stopAll() }
        let firstID = UUID(), secondID = UUID()
        try engine.play(entryId: firstID, url: url, positionMs: 0, startPlaying: true)
        try await Task.sleep(for: .milliseconds(100))
        let outgoing = engine.active
        let spec = duration.map { value in
            var spec = TransitionSpec()
            spec.durationMs = value
            return spec
        }
        try engine.play(entryId: secondID, url: url, positionMs: 0, startPlaying: true, handoffSpec: spec)
        XCTAssertTrue(engine.isRunning)
        XCTAssertFalse(engine.active === outgoing)
        XCTAssertTrue(engine.other === outgoing)
        XCTAssertEqual(engine.currentPosition()?.entryId, secondID)
        XCTAssertEqual(outgoing.segments.first?.entryId, firstID)
        XCTAssertTrue(outgoing.player.isPlaying)
        XCTAssertTrue(outgoing.stage.isEngaged)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertGreaterThan(try XCTUnwrap(engine.currentPosition()).positionMs, 0)
        engine.releaseFinishedOutgoing()
        if duration != nil {
            XCTAssertFalse(engine.other.segments.isEmpty, "The selected fade must outlast the 20 ms anti-click handover")
            try await Task.sleep(for: .seconds(2))
            engine.releaseFinishedOutgoing()
        }
        XCTAssertTrue(engine.other.segments.isEmpty)
    }

    @MainActor
    func testPauseKeepsPositionAndStopsRenderingUntilResume() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132_300)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![channel][frame] = 0 }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let engine = try await readyEngine()
        defer { engine.stopAll() }
        let id = UUID()
        try engine.play(entryId: id, url: url, positionMs: 1_000, startPlaying: true)
        try await Task.sleep(for: .milliseconds(250))
        engine.pause()
        let paused = try XCTUnwrap(engine.currentPosition())
        XCTAssertEqual(paused.entryId, id)
        XCTAssertGreaterThan(paused.positionMs, 1_000)
        XCTAssertFalse(engine.isRunning)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(engine.currentPosition()?.positionMs, paused.positionMs)
        try engine.resume()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(engine.isRunning)
        XCTAssertGreaterThan(try XCTUnwrap(engine.currentPosition()).positionMs, paused.positionMs)
    }
}
