//
//  DittoDrawingModelTests.swift
//  DrawTogetherTests
//
//  Created by Brian Plattenburg on 3/25/26.
//

import XCTest
import PencilKit
@testable import DrawTogether

final class DittoDrawingModelTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a simple PKStroke with a unique creation date
    private func makeStroke(at point: CGPoint = CGPoint(x: 100, y: 100), creationDate: Date = Date()) -> PKStroke {
        let ink = PKInk(.pen, color: .black)
        let path = PKStrokePath(controlPoints: [
            PKStrokePoint(location: point, timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: point.x + 50, y: point.y + 50), timeOffset: 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        ], creationDate: creationDate)
        return PKStroke(ink: ink, path: path)
    }

    /// Encodes a stroke as a JSON string using DittoStrokeModel
    private func encodeStroke(_ stroke: PKStroke) -> String? {
        DittoStrokeModel.encode(stroke)
    }

    // MARK: - Diff Tests

    func testDiffDoesNotDuplicateOnRepeatedCalls() {
        var model = DittoDrawingModel()
        let stroke = makeStroke(at: CGPoint(x: 42, y: 42), creationDate: Date(timeIntervalSince1970: 1000))

        let (inserts1, _) = model.diff(currentStrokes: [stroke])
        let (inserts2, _) = model.diff(currentStrokes: [stroke])

        XCTAssertEqual(inserts1.count, 1, "First diff should detect 1 new stroke")
        XCTAssertTrue(inserts2.isEmpty, "Second diff should produce no inserts — key was persisted on first call")
    }

    // MARK: - Drawing Reconstruction Tests

    func testDrawingRebuildsInSortedOrder() {
        var model = DittoDrawingModel()

        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)

        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date1)
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: date2)
        let stroke3 = makeStroke(at: CGPoint(x: 90, y: 90), creationDate: date3)

        guard let json1 = encodeStroke(stroke1),
              let json2 = encodeStroke(stroke2),
              let json3 = encodeStroke(stroke3) else {
            XCTFail("Failed to encode strokes")
            return
        }

        // Insert with out-of-order keys (timestamps are still chronological in the key string)
        let strokesMap: [String: String] = [
            "2026-03-25T12:00:02.000Z-CCC": json3,
            "2026-03-25T12:00:00.000Z-AAA": json1,
            "2026-03-25T12:00:01.000Z-BBB": json2,
        ]
        model.updateFromStrokesMap(strokesMap)

        let drawing = model.drawing()
        XCTAssertEqual(drawing.strokes.count, 3)

        // Strokes should be in order based on sorted keys (AAA < BBB < CCC)
        XCTAssertEqual(drawing.strokes[0].path.first?.location.x ?? 0, 10, accuracy: 1)
        XCTAssertEqual(drawing.strokes[1].path.first?.location.x ?? 0, 50, accuracy: 1)
        XCTAssertEqual(drawing.strokes[2].path.first?.location.x ?? 0, 90, accuracy: 1)
    }

    // MARK: - Diff Tests

    func testDiffDetectsNewStrokes() {
        var model = DittoDrawingModel()

        let existingDate = Date(timeIntervalSince1970: 1000)
        let existingStroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: existingDate)
        guard let existingJSON = encodeStroke(existingStroke) else {
            XCTFail("Failed to encode stroke")
            return
        }
        model.updateFromStrokesMap(["2026-03-25T12:00:00.000Z-AAA": existingJSON])

        // Canvas now has existing stroke + a new stroke with a different creation date
        let newDate = Date(timeIntervalSince1970: 2000)
        let newStroke = makeStroke(at: CGPoint(x: 200, y: 200), creationDate: newDate)
        let (inserts, removes) = model.diff(currentStrokes: [existingStroke, newStroke])

        XCTAssertEqual(inserts.count, 1, "Should detect 1 new stroke")
        XCTAssertTrue(removes.isEmpty, "Should not detect any removals")
    }

    func testDiffDetectsRemovedStrokes() {
        var model = DittoDrawingModel()

        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date1)
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: date2)
        guard let json1 = encodeStroke(stroke1),
              let json2 = encodeStroke(stroke2) else {
            XCTFail("Failed to encode strokes")
            return
        }
        model.updateFromStrokesMap([
            "2026-03-25T12:00:00.000Z-AAA": json1,
            "2026-03-25T12:00:01.000Z-BBB": json2,
        ])

        // Canvas only has stroke1, stroke2 was removed
        let (inserts, removes) = model.diff(currentStrokes: [stroke1])

        XCTAssertTrue(inserts.isEmpty, "Should not detect any inserts")
        XCTAssertEqual(removes.count, 1, "Should detect 1 removal")
        XCTAssertEqual(removes.first, "2026-03-25T12:00:01.000Z-BBB")
    }

    // MARK: - Apply Tests

    func testApplyUpdatesStrokeMap() {
        var model = DittoDrawingModel()

        let date1 = Date(timeIntervalSince1970: 1000)
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date1)
        guard let json1 = encodeStroke(stroke1) else {
            XCTFail("Failed to encode stroke")
            return
        }
        model.updateFromStrokesMap(["2026-03-25T12:00:00.000Z-AAA": json1])

        // Apply: insert a new stroke, remove existing one
        let date2 = Date(timeIntervalSince1970: 2000)
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: date2)
        guard let json2 = encodeStroke(stroke2) else {
            XCTFail("Failed to encode stroke")
            return
        }
        let newKey = "2026-03-25T12:00:01.000Z-BBB"
        model.apply(inserts: [newKey: json2], removes: ["2026-03-25T12:00:00.000Z-AAA"])

        XCTAssertEqual(model.strokeMap.count, 1)
        XCTAssertNotNil(model.strokeMap[newKey])
        XCTAssertNil(model.strokeMap["2026-03-25T12:00:00.000Z-AAA"])

        // Subsequent diff against the same strokes should produce no changes
        let (inserts, removes) = model.diff(currentStrokes: [stroke2])
        XCTAssertTrue(inserts.isEmpty, "No inserts expected after apply")
        XCTAssertTrue(removes.isEmpty, "No removes expected after apply")
    }

    func testApplyKeepsReverseMapsConsistent() {
        var model = DittoDrawingModel()

        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date1)
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: date2)
        let stroke3 = makeStroke(at: CGPoint(x: 90, y: 90), creationDate: date3)
        guard let json1 = encodeStroke(stroke1),
              let json2 = encodeStroke(stroke2),
              let json3 = encodeStroke(stroke3) else {
            XCTFail("Failed to encode strokes")
            return
        }

        let key1 = "2026-03-25T12:00:00.000Z-AAA"
        let key2 = "2026-03-25T12:00:01.000Z-BBB"
        let key3 = "2026-03-25T12:00:02.000Z-CCC"

        model.updateFromStrokesMap([key1: json1, key2: json2])

        // Verify reverse map is populated
        XCTAssertEqual(model.keyToCreationDate[key1], date1)
        XCTAssertEqual(model.keyToCreationDate[key2], date2)

        // Apply: remove key1, add key3
        model.apply(inserts: [key3: json3], removes: [key1])

        // Verify both maps are consistent after apply
        XCTAssertNil(model.keyToCreationDate[key1], "Removed key should be gone from reverse map")
        XCTAssertNil(model.creationDateToKey[date1], "Removed date should be gone from forward map")
        XCTAssertEqual(model.keyToCreationDate[key3], date3, "Inserted key should be in reverse map")
        XCTAssertEqual(model.creationDateToKey[date3], key3, "Inserted date should be in forward map")

        // Existing entry should be untouched
        XCTAssertEqual(model.keyToCreationDate[key2], date2)
        XCTAssertEqual(model.creationDateToKey[date2], key2)
    }

    func testRollbackPendingKeysAllowsReSync() {
        var model = DittoDrawingModel()

        let stroke = makeStroke(at: CGPoint(x: 42, y: 42), creationDate: Date(timeIntervalSince1970: 1000))

        // First diff persists key mappings optimistically
        let (inserts1, _) = model.diff(currentStrokes: [stroke])
        XCTAssertEqual(inserts1.count, 1)

        // Second diff sees stroke as known — no inserts
        let (inserts2, _) = model.diff(currentStrokes: [stroke])
        XCTAssertTrue(inserts2.isEmpty)

        // Rollback simulates a failed transaction
        model.rollbackPendingKeys(inserts: inserts1)

        // After rollback, the stroke should be detected as new again
        let (inserts3, _) = model.diff(currentStrokes: [stroke])
        XCTAssertEqual(inserts3.count, 1, "Stroke should be re-detected after rollback")
    }

    func testUpdateFromStrokesMapClearsStateOnEmptyMap() {
        var model = DittoDrawingModel()

        let date1 = Date(timeIntervalSince1970: 1000)
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date1)
        guard let json1 = encodeStroke(stroke1) else {
            XCTFail("Failed to encode stroke")
            return
        }

        model.updateFromStrokesMap(["2026-03-25T12:00:00.000Z-AAA": json1])
        XCTAssertEqual(model.strokeMap.count, 1)

        // Updating with a new map replaces state entirely
        model.updateFromStrokesMap([:])
        XCTAssertTrue(model.strokeMap.isEmpty)
        XCTAssertTrue(model.creationDateToKey.isEmpty)
        XCTAssertTrue(model.keyToCreationDate.isEmpty)
    }

}
