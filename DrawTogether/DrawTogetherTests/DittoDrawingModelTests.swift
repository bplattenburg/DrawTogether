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

    private func makeStroke(at point: CGPoint = CGPoint(x: 100, y: 100), creationDate: Date = Date()) -> PKStroke {
        let ink = PKInk(.pen, color: .black)
        let path = PKStrokePath(controlPoints: [
            PKStrokePoint(location: point, timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: point.x + 50, y: point.y + 50), timeOffset: 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        ], creationDate: creationDate)
        return PKStroke(ink: ink, path: path)
    }

    private func encodeStroke(_ stroke: PKStroke) -> String? {
        DittoStrokeModel.encode(stroke)
    }

    /// Populates the given model with the provided strokes.
    private func modelWithKnownStrokes(_ model: inout DittoDrawingModel, strokes: [(stroke: PKStroke, key: String)]) {
        var map: [String: String] = [:]
        for (stroke, key) in strokes {
            guard let encoded = encodeStroke(stroke) else {
                XCTFail("Failed to encode stroke")
                return
            }
            map[key] = encoded
        }
        model.updateFromStrokesMap(map)
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

        modelWithKnownStrokes(&model, strokes: [
            (stroke1, "2026-03-25T12:00:00.000Z-AAA"),
            (stroke2, "2026-03-25T12:00:01.000Z-BBB"),
            (stroke3, "2026-03-25T12:00:02.000Z-CCC"),
        ])

        let drawing = model.drawing()
        XCTAssertEqual(drawing.strokes.count, 3)
        XCTAssertEqual(drawing.strokes[0].path.first?.location.x ?? 0, 10, accuracy: 1)
        XCTAssertEqual(drawing.strokes[1].path.first?.location.x ?? 0, 50, accuracy: 1)
        XCTAssertEqual(drawing.strokes[2].path.first?.location.x ?? 0, 90, accuracy: 1)
    }

    // MARK: - Build Desired State Tests

    func testBuildDesiredStateNewStrokes() {
        let model = DittoDrawingModel()
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))

        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [stroke1, stroke2],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertEqual(result.desired.count, 2)
        XCTAssertTrue(result.removes.isEmpty)
        XCTAssertEqual(result.newMappings.count, 2)
    }

    func testBuildDesiredStateReusesExistingKeys() {
        var model = DittoDrawingModel()
        let date = Date(timeIntervalSince1970: 1000)
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date)
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(stroke, key)])

        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [stroke],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertEqual(result.desired.count, 1)
        XCTAssertNotNil(result.desired[key], "Should reuse existing key")
        XCTAssertTrue(result.newMappings.isEmpty, "Known stroke should not generate new mapping")
    }

    func testBuildDesiredStateReusesEncodingForUnchangedStrokes() {
        var model = DittoDrawingModel()
        let date = Date(timeIntervalSince1970: 1000)
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date)
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(stroke, key)])
        let storedEncoding = model.strokeMap[key]!

        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [stroke],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertEqual(result.desired[key], storedEncoding,
                        "Unchanged stroke should reuse exact stored encoding (byte-identical)")
    }

    func testBuildDesiredStateReencodesWhenMaskAdded() {
        var model = DittoDrawingModel()
        let date = Date(timeIntervalSince1970: 1000)
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date)
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(stroke, key)])
        let storedEncoding = model.strokeMap[key]!

        // Apply mask to the stroke
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let maskedStroke = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: mask)

        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [maskedStroke],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertEqual(result.desired.count, 1)
        XCTAssertNotEqual(result.desired[key], storedEncoding, "Masked stroke should be re-encoded")
        XCTAssertTrue(result.newMappings.isEmpty, "Same key should be reused")
        XCTAssertTrue(result.removes.isEmpty)
    }

    func testBuildDesiredStateReencodesWhenMaskChanged() {
        var model = DittoDrawingModel()
        let date = Date(timeIntervalSince1970: 1000)
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date)
        let maskA = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let maskedStrokeA = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: maskA)
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(maskedStrokeA, key)])
        let storedEncoding = model.strokeMap[key]!

        // Change the mask
        let maskB = UIBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 100, height: 100))
        let maskedStrokeB = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: maskB)

        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [maskedStrokeB],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertNotEqual(result.desired[key], storedEncoding, "Changed mask should trigger re-encoding")
    }

    func testBuildDesiredStateReencodesWhenMaskRemoved() {
        var model = DittoDrawingModel()
        let date = Date(timeIntervalSince1970: 1000)
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date)
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let maskedStroke = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: mask)
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(maskedStroke, key)])
        let storedEncoding = model.strokeMap[key]!

        // Undo: stroke without mask (same creationDate)
        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [stroke],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertNotEqual(result.desired[key], storedEncoding, "Mask removal should trigger re-encoding")
    }

    func testBuildDesiredStateDetectsRemoves() {
        var model = DittoDrawingModel()
        let strokeA = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let strokeB = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))
        let keyA = "2026-03-25T12:00:00.000Z"
        let keyB = "2026-03-25T12:00:01.000Z"

        modelWithKnownStrokes(&model, strokes: [(strokeA, keyA), (strokeB, keyB)])

        // Canvas only has strokeA — strokeB was removed
        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [strokeA],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertEqual(result.desired.count, 1)
        XCTAssertEqual(result.removes, [keyB])
    }

    func testBuildDesiredStateMixed() {
        var model = DittoDrawingModel()
        let strokeA = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let strokeB = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))
        let keyA = "2026-03-25T12:00:00.000Z"
        let keyB = "2026-03-25T12:00:01.000Z"

        modelWithKnownStrokes(&model, strokes: [(strokeA, keyA), (strokeB, keyB)])

        // Modify A (add mask), remove B, add new stroke C
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let maskedA = PKStroke(ink: strokeA.ink, path: strokeA.path, transform: strokeA.transform, mask: mask)
        let strokeC = makeStroke(at: CGPoint(x: 90, y: 90), creationDate: Date(timeIntervalSince1970: 3000))

        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [maskedA, strokeC],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertEqual(result.desired.count, 2, "A (modified) + C (new)")
        XCTAssertNotNil(result.desired[keyA], "A should use existing key")
        XCTAssertEqual(result.removes, [keyB], "B should be removed")
        XCTAssertEqual(result.newMappings.count, 1, "C is the only new stroke")
    }

    func testBuildDesiredStateEmptyCanvas() {
        var model = DittoDrawingModel()
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(stroke, key)])

        let result = DittoDrawingModel.buildDesiredState(
            currentStrokes: [],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )

        XCTAssertTrue(result.desired.isEmpty)
        XCTAssertEqual(result.removes, [key])
    }

    // MARK: - Persist / Rollback Tests

    func testPersistPendingPreventsRedundantMappings() {
        var model = DittoDrawingModel()
        let stroke = makeStroke(at: CGPoint(x: 42, y: 42), creationDate: Date(timeIntervalSince1970: 1000))

        let result1 = DittoDrawingModel.buildDesiredState(
            currentStrokes: [stroke],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )
        XCTAssertEqual(result1.newMappings.count, 1)

        _ = model.persistPending(newMappings: result1.newMappings, desired: result1.desired, currentStrokes: [stroke])

        let result2 = DittoDrawingModel.buildDesiredState(
            currentStrokes: [stroke],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )
        XCTAssertTrue(result2.newMappings.isEmpty, "Second call should produce no new mappings")
    }

    func testRollbackPendingAllowsReDetection() {
        var model = DittoDrawingModel()
        let stroke = makeStroke(at: CGPoint(x: 42, y: 42), creationDate: Date(timeIntervalSince1970: 1000))

        let result1 = DittoDrawingModel.buildDesiredState(
            currentStrokes: [stroke],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )
        let oldValues = model.persistPending(newMappings: result1.newMappings, desired: result1.desired, currentStrokes: [stroke])

        model.rollbackPending(oldValues: oldValues, newMappings: result1.newMappings)

        let result2 = DittoDrawingModel.buildDesiredState(
            currentStrokes: [stroke],
            knownCreationDateToKey: model.creationDateToKey,
            knownStrokeMap: model.strokeMap,
            knownMaskFingerprints: model.maskFingerprints
        )
        XCTAssertEqual(result2.newMappings.count, 1, "Stroke should be re-detected after rollback")
    }

    // MARK: - Apply Removes Tests

    func testApplyRemovesCleansMaps() {
        var model = DittoDrawingModel()
        let date = Date(timeIntervalSince1970: 1000)
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: date)
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let maskedStroke = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: mask)
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(maskedStroke, key)])
        XCTAssertNotNil(model.maskFingerprints[key])

        model.applyRemoves([key])

        XCTAssertNil(model.strokeMap[key])
        XCTAssertNil(model.creationDateToKey[date])
        XCTAssertNil(model.keyToCreationDate[key])
        XCTAssertNil(model.maskFingerprints[key])
    }

    func testApplyRemovesLeavesOtherStrokesIntact() {
        var model = DittoDrawingModel()
        let strokeA = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let strokeB = makeStroke(at: CGPoint(x: 50, y: 50), creationDate: Date(timeIntervalSince1970: 2000))
        let keyA = "2026-03-25T12:00:00.000Z"
        let keyB = "2026-03-25T12:00:01.000Z"

        modelWithKnownStrokes(&model, strokes: [(strokeA, keyA), (strokeB, keyB)])

        model.applyRemoves([keyA])

        XCTAssertNil(model.strokeMap[keyA])
        XCTAssertNotNil(model.strokeMap[keyB], "Other stroke should be untouched")
        XCTAssertEqual(model.creationDateToKey[Date(timeIntervalSince1970: 2000)], keyB)
    }

    // MARK: - Update From Strokes Map Tests

    func testUpdateFromStrokesMapPopulatesFingerprints() {
        var model = DittoDrawingModel()
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let maskedStroke = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: mask)
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(maskedStroke, key)])

        XCTAssertNotNil(model.maskFingerprints[key], "Masked stroke should have a fingerprint")
    }

    func testUpdateFromStrokesMapNoFingerprintForUnmaskedStroke() {
        var model = DittoDrawingModel()
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))
        let key = "2026-03-25T12:00:00.000Z"

        modelWithKnownStrokes(&model, strokes: [(stroke, key)])

        XCTAssertNil(model.maskFingerprints[key], "Unmasked stroke should have no fingerprint")
    }

    func testUpdateFromStrokesMapClearsStateOnEmptyMap() {
        var model = DittoDrawingModel()
        let stroke = makeStroke(at: CGPoint(x: 10, y: 10), creationDate: Date(timeIntervalSince1970: 1000))

        modelWithKnownStrokes(&model, strokes: [(stroke, "2026-03-25T12:00:00.000Z")])
        XCTAssertEqual(model.strokeMap.count, 1)

        model.updateFromStrokesMap([:])
        XCTAssertTrue(model.strokeMap.isEmpty)
        XCTAssertTrue(model.creationDateToKey.isEmpty)
        XCTAssertTrue(model.keyToCreationDate.isEmpty)
        XCTAssertTrue(model.maskFingerprints.isEmpty)
    }
}
