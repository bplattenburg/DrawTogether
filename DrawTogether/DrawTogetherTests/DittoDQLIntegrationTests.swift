//
//  DittoDQLIntegrationTests.swift
//  DrawTogetherTests
//
//  Created by Brian Plattenburg on 3/25/26.
//

import XCTest
import PencilKit
import DittoSwift
@testable import DrawTogether

/// Integration tests that verify DQL queries work correctly against a real local Ditto instance.
/// Uses offline playground identity with no sync started.
final class DittoDQLIntegrationTests: XCTestCase {

    private var ditto: Ditto!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ditto = Ditto(identity: .offlinePlayground(), persistenceDirectory: dir)
        try ditto.disableSyncWithV3()
        try await ditto.store.execute(query: "ALTER SYSTEM SET DQL_STRICT_MODE = false")
    }

    override func tearDown() async throws {
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

    // MARK: - Insert Tests

    func testInsertStrokesMapMergesCorrectly() async throws {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))

        guard let encoded1 = DittoStrokeModel.encode(stroke1),
              let encoded2 = DittoStrokeModel.encode(stroke2) else {
            XCTFail("Failed to encode strokes")
            return
        }

        let key1 = DittoStrokeModel.generateKey(for: stroke1.path.creationDate, encodedData: encoded1.data)
        let key2 = DittoStrokeModel.generateKey(for: stroke2.path.creationDate, encodedData: encoded2.data)

        // Insert first stroke
        let doc1: [String: Any] = ["_id": "1", "strokes": [key1: encoded1.json]]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc1]
        )

        // Insert second stroke via merge — should add to existing strokes map
        let doc2: [String: Any] = ["_id": "1", "strokes": [key2: encoded2.json]]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc2]
        )

        // Verify both strokes are present
        let result = try await ditto.store.execute(query: "SELECT * FROM drawings WHERE _id = '1'")
        XCTAssertEqual(result.items.count, 1)

        guard let strokesMap = result.items.first?.value["strokes"] as? [String: Any] else {
            XCTFail("Expected strokes map in document")
            return
        }

        XCTAssertEqual(strokesMap.count, 2, "Both strokes should be present after merge")
        XCTAssertNotNil(strokesMap[key1])
        XCTAssertNotNil(strokesMap[key2])
    }

    func testBatchInsertMergesAllStrokes() async throws {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))
        let stroke3 = makeStroke(at: CGPoint(x: 90, y: 90), creationDate: Date(timeIntervalSince1970: 3000))

        guard let e1 = DittoStrokeModel.encode(stroke1),
              let e2 = DittoStrokeModel.encode(stroke2),
              let e3 = DittoStrokeModel.encode(stroke3) else {
            XCTFail("Failed to encode strokes")
            return
        }

        let key1 = DittoStrokeModel.generateKey(for: stroke1.path.creationDate, encodedData: e1.data)
        let key2 = DittoStrokeModel.generateKey(for: stroke2.path.creationDate, encodedData: e2.data)
        let key3 = DittoStrokeModel.generateKey(for: stroke3.path.creationDate, encodedData: e3.data)

        // Batch insert all strokes in one merge
        let allStrokes: [String: String] = [key1: e1.json, key2: e2.json, key3: e3.json]
        let doc: [String: Any] = ["_id": "1", "strokes": allStrokes]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc]
        )

        let result = try await ditto.store.execute(query: "SELECT * FROM drawings WHERE _id = '1'")
        guard let strokesMap = result.items.first?.value["strokes"] as? [String: Any] else {
            XCTFail("Expected strokes map")
            return
        }
        XCTAssertEqual(strokesMap.count, 3)
    }

    // MARK: - UNSET Tests

    func testUnsetRemovesStrokeFromMap() async throws {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))

        guard let e1 = DittoStrokeModel.encode(stroke1),
              let e2 = DittoStrokeModel.encode(stroke2) else {
            XCTFail("Failed to encode strokes")
            return
        }

        let key1 = DittoStrokeModel.generateKey(for: stroke1.path.creationDate, encodedData: e1.data)
        let key2 = DittoStrokeModel.generateKey(for: stroke2.path.creationDate, encodedData: e2.data)

        // Insert both strokes
        let doc: [String: Any] = ["_id": "1", "strokes": [key1: e1.json, key2: e2.json]]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc]
        )

        // UNSET one stroke using backtick-quoted key
        try await ditto.store.execute(
            query: "UPDATE drawings UNSET strokes.`\(key1)` WHERE _id = :drawingID",
            arguments: ["drawingID": "1"]
        )

        // Verify only stroke2 remains
        let result = try await ditto.store.execute(query: "SELECT * FROM drawings WHERE _id = '1'")
        guard let strokesMap = result.items.first?.value["strokes"] as? [String: Any] else {
            XCTFail("Expected strokes map")
            return
        }

        XCTAssertEqual(strokesMap.count, 1, "Only one stroke should remain after UNSET")
        XCTAssertNil(strokesMap[key1], "Unset stroke should be gone")
        XCTAssertNotNil(strokesMap[key2], "Other stroke should still be present")
    }

    // MARK: - Transaction Tests

    func testTransactionInsertsAndUnsetsAtomically() async throws {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))
        let stroke3 = makeStroke(at: CGPoint(x: 90, y: 90), creationDate: Date(timeIntervalSince1970: 3000))

        guard let e1 = DittoStrokeModel.encode(stroke1),
              let e2 = DittoStrokeModel.encode(stroke2),
              let e3 = DittoStrokeModel.encode(stroke3) else {
            XCTFail("Failed to encode strokes")
            return
        }

        let key1 = DittoStrokeModel.generateKey(for: stroke1.path.creationDate, encodedData: e1.data)
        let key2 = DittoStrokeModel.generateKey(for: stroke2.path.creationDate, encodedData: e2.data)
        let key3 = DittoStrokeModel.generateKey(for: stroke3.path.creationDate, encodedData: e3.data)

        // Insert initial strokes
        let doc: [String: Any] = ["_id": "1", "strokes": [key1: e1.json, key2: e2.json]]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc]
        )

        // Transaction: add stroke3, remove stroke1
        try await ditto.store.transaction { transaction in
            let insertDoc: [String: Any] = ["_id": "1", "strokes": [key3: e3.json]]
            try await transaction.execute(
                query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
                arguments: ["doc": insertDoc]
            )
            try await transaction.execute(
                query: "UPDATE drawings UNSET strokes.`\(key1)` WHERE _id = :drawingID",
                arguments: ["drawingID": "1"]
            )
            return .commit
        }

        // Verify: stroke2 and stroke3 remain, stroke1 is gone
        let result = try await ditto.store.execute(query: "SELECT * FROM drawings WHERE _id = '1'")
        guard let strokesMap = result.items.first?.value["strokes"] as? [String: Any] else {
            XCTFail("Expected strokes map")
            return
        }

        XCTAssertEqual(strokesMap.count, 2)
        XCTAssertNil(strokesMap[key1], "Stroke1 should be removed")
        XCTAssertNotNil(strokesMap[key2], "Stroke2 should remain")
        XCTAssertNotNil(strokesMap[key3], "Stroke3 should be added")
    }

    // MARK: - Observer Tests

    func testObserverFiltersByDrawingID() async throws {
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10))
        guard let encoded = DittoStrokeModel.encode(stroke) else {
            XCTFail("Failed to encode stroke")
            return
        }
        let key = DittoStrokeModel.generateKey(for: stroke.path.creationDate, encodedData: encoded.data)

        // Insert into drawing "1"
        let doc1: [String: Any] = ["_id": "1", "strokes": [key: encoded.json]]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc1]
        )

        // Insert into drawing "2" (different document)
        let doc2: [String: Any] = ["_id": "2", "strokes": ["other-key": encoded.json]]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc2]
        )

        // Observer filtered by drawingID "1" should only see document "1"
        let expectation = expectation(description: "Observer fires")
        var observedItems: [DittoSwift.DittoQueryResultItem] = []

        let observer = try ditto.store.registerObserver(
            query: "SELECT * FROM drawings WHERE _id = :drawingID",
            arguments: ["drawingID": "1"]
        ) { result in
            observedItems = result.items
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
        observer.cancel()

        XCTAssertEqual(observedItems.count, 1, "Should only observe the filtered document")
        XCTAssertEqual(observedItems.first?.value["_id"] as? String, "1")
    }

    // MARK: - Full Round-Trip Test

    func testFullRoundTripWithDittoDrawingModel() async throws {
        var model = DittoDrawingModel(drawingID: "test-drawing")

        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))

        // Diff to get inserts
        let (inserts, _) = model.diff(currentStrokes: [stroke1, stroke2])
        XCTAssertEqual(inserts.count, 2)

        // Insert into Ditto
        let doc: [String: Any] = ["_id": model.drawingID, "strokes": inserts]
        try await ditto.store.execute(
            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
            arguments: ["doc": doc]
        )
        model.apply(inserts: inserts, removes: [])

        // Read back from Ditto and update model
        let result = try await ditto.store.execute(
            query: "SELECT * FROM drawings WHERE _id = :id",
            arguments: ["id": model.drawingID]
        )
        guard let item = result.items.first,
              let rawMap = item.value["strokes"] as? [String: Any] else {
            XCTFail("Expected strokes in Ditto")
            return
        }

        var strokesMap: [String: String] = [:]
        for (key, value) in rawMap {
            if let str = value as? String { strokesMap[key] = str }
        }

        var readModel = DittoDrawingModel(drawingID: "test-drawing")
        readModel.updateFromStrokesMap(strokesMap)
        let drawing = readModel.drawing()

        XCTAssertEqual(drawing.strokes.count, 2, "Should reconstruct 2 strokes from Ditto")

        // Now remove stroke1
        let (_, removes) = readModel.diff(currentStrokes: [stroke2])
        XCTAssertEqual(removes.count, 1)

        for key in removes {
            try await ditto.store.execute(
                query: "UPDATE drawings UNSET strokes.`\(key)` WHERE _id = :drawingID",
                arguments: ["drawingID": model.drawingID]
            )
        }
        readModel.apply(inserts: [:], removes: removes)

        // Verify only stroke2 remains
        let result2 = try await ditto.store.execute(
            query: "SELECT * FROM drawings WHERE _id = :id",
            arguments: ["id": model.drawingID]
        )
        guard let strokesMap2 = result2.items.first?.value["strokes"] as? [String: Any] else {
            XCTFail("Expected strokes")
            return
        }
        XCTAssertEqual(strokesMap2.count, 1, "Only one stroke should remain after UNSET")
        XCTAssertEqual(readModel.drawing().strokes.count, 1)
    }
}
