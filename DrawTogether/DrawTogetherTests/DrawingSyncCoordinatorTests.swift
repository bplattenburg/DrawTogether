//
//  DrawingSyncCoordinatorTests.swift
//  DrawTogetherTests
//
//  Created by Brian Plattenburg on 3/25/26.
//

import XCTest
import PencilKit
import DittoSwift
@testable import DrawTogether

/// Integration tests that exercise the full DrawingSyncCoordinator flow against a real local Ditto instance.
/// Uses offline playground identity with no sync started.
@MainActor
final class DrawingSyncCoordinatorTests: XCTestCase {

    private var ditto: Ditto!
    private var coordinator: DrawingSyncCoordinator!
    private var canvasView: PKCanvasView!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ditto = Ditto(identity: .offlinePlayground(), persistenceDirectory: dir)
        try ditto.disableSyncWithV3()
        try await ditto.store.execute(query: "ALTER SYSTEM SET DQL_STRICT_MODE = false")

        // Create coordinator with injected test Ditto and no debounce delay
        let parent = CanvasView(drawing: .constant(PKDrawing()), toolPicker: .constant(nil))
        coordinator = DrawingSyncCoordinator(parent, ditto: ditto, syncDebounceNanoseconds: 0)

        canvasView = PKCanvasView()
        coordinator.canvasView = canvasView
    }

    override func tearDown() async throws {
        coordinator = nil
        canvasView = nil
        ditto = nil
    }

    // MARK: - Helpers

    private func makeStroke(at point: CGPoint = CGPoint(x: 100, y: 100), creationDate: Date = Date()) -> PKStroke {
        let ink = PKInk(.pen, color: .black)
        let path = PKStrokePath(controlPoints: [
            PKStrokePoint(location: point, timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: point.x + 50, y: point.y + 50), timeOffset: 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        ], creationDate: creationDate)
        return PKStroke(ink: ink, path: path)
    }

    private func queryStrokesMap() async throws -> [String: Any] {
        let result = try await ditto.store.execute(
            query: "SELECT * FROM drawings WHERE _id = :id",
            arguments: ["id": coordinator.model.drawingID]
        )
        return result.items.first?.value["strokes"] as? [String: Any] ?? [:]
    }

    /// Triggers a canvas drawing change and waits for Ditto to reach the expected stroke count.
    /// Uses a Ditto store observer to fulfill the expectation — no timers or polling.
    private func triggerSyncAndWaitForDitto(expectedStrokeCount: Int, timeout: TimeInterval = 5.0) async throws {
        let exp = expectation(description: "Ditto has \(expectedStrokeCount) strokes")

        let observer = try ditto.store.registerObserver(
            query: "SELECT * FROM drawings WHERE _id = :id",
            arguments: ["id": coordinator.model.drawingID]
        ) { result in
            guard let item = result.items.first,
                  let strokes = item.value["strokes"] as? [String: Any],
                  strokes.count == expectedStrokeCount else { return }
            exp.fulfill()
        }

        coordinator.canvasViewDrawingDidChange(canvasView)
        await fulfillment(of: [exp], timeout: timeout)
        observer.cancel()
    }

    /// Waits for the coordinator's model to reach the expected stroke count.
    /// Hooks into the coordinator's onModelUpdate callback — no separate observers, timers, or polling.
    private func waitForModel(strokeCount: Int, timeout: TimeInterval = 5.0) async {
        // If already at expected count, return immediately
        guard coordinator.model.strokeMap.count != strokeCount else { return }

        let exp = expectation(description: "Model has \(strokeCount) strokes")
        coordinator.onModelUpdate = { [weak self] in
            guard let self, self.coordinator.model.strokeMap.count == strokeCount else { return }
            exp.fulfill()
            self.coordinator.onModelUpdate = nil
        }

        await fulfillment(of: [exp], timeout: timeout)
    }

    // MARK: - Outbound Sync Tests

    func testNewStrokesSyncToDitto() async throws {
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        canvasView.drawing = PKDrawing(strokes: [stroke])

        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 1)
    }

    func testMultipleStrokesSyncInBatch() async throws {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))
        let stroke3 = makeStroke(at: CGPoint(x: 90, y: 90), creationDate: Date(timeIntervalSince1970: 3000))
        canvasView.drawing = PKDrawing(strokes: [stroke1, stroke2, stroke3])

        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 3)
    }

    func testRemovedStrokesUnsetFromDitto() async throws {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))

        // Sync both strokes
        canvasView.drawing = PKDrawing(strokes: [stroke1, stroke2])
        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 2)

        // Remove stroke1 from canvas, keep stroke2
        canvasView.drawing = PKDrawing(strokes: [stroke2])
        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 1)
    }

    func testMixedInsertAndRemoveInSingleSync() async throws {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))

        // Sync stroke1 and stroke2
        canvasView.drawing = PKDrawing(strokes: [stroke1, stroke2])
        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 2)

        // Replace stroke1 with stroke3, keep stroke2
        let stroke3 = makeStroke(at: CGPoint(x: 90, y: 90), creationDate: Date(timeIntervalSince1970: 3000))
        canvasView.drawing = PKDrawing(strokes: [stroke2, stroke3])
        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 2)
    }

    // MARK: - Inbound Sync Tests

    func testObserverUpdatesModelOnRemoteInsert() async throws {
        // Sync a stroke through the coordinator first
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        canvasView.drawing = PKDrawing(strokes: [stroke1])
        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 1)

        XCTAssertEqual(coordinator.model.strokeMap.count, 1)

        // Simulate a remote insert directly into Ditto
        let remoteStroke = makeStroke(at: CGPoint(x: 200, y: 200), creationDate: Date(timeIntervalSince1970: 5000))
        guard let remoteJSON = DittoStrokeModel.encode(remoteStroke) else {
            XCTFail("Failed to encode remote stroke")
            return
        }
        let remoteKey = DittoStrokeModel.generateKey(for: remoteStroke.path.creationDate)
        let doc: [String: Any] = ["_id": coordinator.model.drawingID, "strokes": [remoteKey: remoteJSON]]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc]
        )

        // Wait for the coordinator's observer to update the model
        await waitForModel(strokeCount: 2)
    }

    // MARK: - Round-Trip Tests

    func testFullRoundTrip() async throws {
        // 1. Draw two strokes and sync
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))
        canvasView.drawing = PKDrawing(strokes: [stroke1, stroke2])
        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 2)

        // 2. Verify model can reconstruct a drawing with correct stroke count
        XCTAssertEqual(coordinator.model.drawing().strokes.count, 2)

        // 3. Remove one stroke and sync
        canvasView.drawing = PKDrawing(strokes: [stroke2])
        try await triggerSyncAndWaitForDitto(expectedStrokeCount: 1)

        // 4. Verify model has one
        XCTAssertEqual(coordinator.model.drawing().strokes.count, 1)
    }
}
