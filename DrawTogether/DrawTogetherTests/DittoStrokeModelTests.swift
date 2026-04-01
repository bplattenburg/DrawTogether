//
//  DittoStrokeModelTests.swift
//  DrawTogetherTests
//
//  Created by Brian Plattenburg on 3/25/26.
//

import XCTest
import PencilKit
@testable import DrawTogether

final class DittoStrokeModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeStroke(at point: CGPoint = CGPoint(x: 100, y: 100), creationDate: Date = Date()) -> PKStroke {
        let ink = PKInk(.pen, color: .black)
        let path = PKStrokePath(controlPoints: [
            PKStrokePoint(location: point, timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: point.x + 50, y: point.y + 50), timeOffset: 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        ], creationDate: creationDate)
        return PKStroke(ink: ink, path: path)
    }

    // MARK: - Encode/Decode Tests

    func testDecodeGroupReturnsEmptyForInvalidInput() {
        XCTAssertTrue(DittoStrokeModel.decodeGroup(from: "not valid base64!@#").isEmpty)
        XCTAssertTrue(DittoStrokeModel.decodeGroup(from: "").isEmpty)
        // Valid base64 but not a PKDrawing
        XCTAssertTrue(DittoStrokeModel.decodeGroup(from: "aGVsbG8=").isEmpty)
    }

    func testEncodeGroupReturnsNilForEmptyArray() {
        XCTAssertNil(DittoStrokeModel.encodeGroup([]))
    }

    // MARK: - Mask Fingerprint Tests

    func testMaskFingerprintNilForNoMask() {
        let stroke = makeStroke()
        XCTAssertNil(DittoStrokeModel.maskFingerprint(for: stroke))
    }

    func testMaskFingerprintStableForSameMask() {
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: makeStroke().path, transform: .identity, mask: mask)
        let fp1 = DittoStrokeModel.maskFingerprint(for: stroke)
        let fp2 = DittoStrokeModel.maskFingerprint(for: stroke)
        XCTAssertNotNil(fp1)
        XCTAssertEqual(fp1, fp2, "Same mask should produce identical fingerprints")
    }

    func testMaskFingerprintDiffersForDifferentMasks() {
        let base = makeStroke()
        let maskA = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let maskB = UIBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 100, height: 100))
        let strokeA = PKStroke(ink: base.ink, path: base.path, transform: base.transform, mask: maskA)
        let strokeB = PKStroke(ink: base.ink, path: base.path, transform: base.transform, mask: maskB)
        let fpA = DittoStrokeModel.maskFingerprint(for: strokeA)
        let fpB = DittoStrokeModel.maskFingerprint(for: strokeB)
        XCTAssertNotNil(fpA)
        XCTAssertNotNil(fpB)
        XCTAssertNotEqual(fpA, fpB, "Different masks should produce different fingerprints")
    }

    // MARK: - Group Fingerprint Tests

    func testGroupFingerprintChangesWithStrokeCount() {
        let stroke = makeStroke()
        let fp1 = DittoStrokeModel.groupFingerprint(for: [stroke])
        let fp2 = DittoStrokeModel.groupFingerprint(for: [stroke, stroke])
        XCTAssertNotEqual(fp1, fp2, "Different stroke counts should produce different fingerprints")
    }

    func testGroupFingerprintStableForSameGroup() {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10))
        let stroke2 = makeStroke(at: CGPoint(x: 50, y: 50))
        let fp1 = DittoStrokeModel.groupFingerprint(for: [stroke1, stroke2])
        let fp2 = DittoStrokeModel.groupFingerprint(for: [stroke1, stroke2])
        XCTAssertEqual(fp1, fp2, "Same group should produce identical fingerprints")
    }

    func testGroupFingerprintChangesWhenMaskAdded() {
        let stroke = makeStroke()
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let maskedStroke = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: mask)

        let fpBefore = DittoStrokeModel.groupFingerprint(for: [stroke])
        let fpAfter = DittoStrokeModel.groupFingerprint(for: [maskedStroke])
        XCTAssertNotEqual(fpBefore, fpAfter, "Adding a mask should change the group fingerprint")
    }

    func testGroupFingerprintSensitiveToOrder() {
        let stroke1 = makeStroke(at: CGPoint(x: 10, y: 10))
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let stroke2 = PKStroke(ink: stroke1.ink, path: makeStroke(at: CGPoint(x: 50, y: 50)).path, transform: .identity, mask: mask)

        let fpAB = DittoStrokeModel.groupFingerprint(for: [stroke1, stroke2])
        let fpBA = DittoStrokeModel.groupFingerprint(for: [stroke2, stroke1])
        XCTAssertNotEqual(fpAB, fpBA, "Different stroke order should produce different fingerprints")
    }

    // MARK: - Key Generation Tests

    func testGenerateKeyUniqueness() {
        var keys = Set<String>()
        let baseDate = Date()
        for i in 0..<100 {
            let date = baseDate.addingTimeInterval(Double(i) * 0.001)
            keys.insert(DittoStrokeModel.generateKey(for: date))
        }
        XCTAssertEqual(keys.count, 100, "All 100 generated keys should be unique")
    }

    func testGenerateKeyIsDeterministic() {
        let date = Date(timeIntervalSince1970: 1000)
        let key1 = DittoStrokeModel.generateKey(for: date)
        let key2 = DittoStrokeModel.generateKey(for: date)
        XCTAssertEqual(key1, key2, "Same date should always produce the same key")
    }

    func testGenerateKeysSortChronologically() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)
        let keys = [
            DittoStrokeModel.generateKey(for: date3),
            DittoStrokeModel.generateKey(for: date1),
            DittoStrokeModel.generateKey(for: date2),
        ]
        XCTAssertEqual(keys.sorted(), [
            DittoStrokeModel.generateKey(for: date1),
            DittoStrokeModel.generateKey(for: date2),
            DittoStrokeModel.generateKey(for: date3),
        ], "Keys should sort in chronological order")
    }
}
