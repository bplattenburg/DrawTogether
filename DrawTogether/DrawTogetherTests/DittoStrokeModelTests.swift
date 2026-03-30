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

    func testRoundTripPreservesContent() {
        let originalStroke = makeStroke(at: CGPoint(x: 42, y: 42))

        guard let encoded = DittoStrokeModel.encode(originalStroke),
              let roundTrippedStroke = DittoStrokeModel.decode(from: encoded) else {
            XCTFail("Round-trip encoding/decoding failed")
            return
        }

        XCTAssertEqual(roundTrippedStroke.path.count, originalStroke.path.count)
        XCTAssertEqual(roundTrippedStroke.path.first?.location.x ?? 0, 42, accuracy: 1)
        XCTAssertEqual(roundTrippedStroke.path.first?.location.y ?? 0, 42, accuracy: 1)
        XCTAssertEqual(roundTrippedStroke.ink.inkType, originalStroke.ink.inkType)
    }

    func testRoundTripPreservesMask() {
        let mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = makeStroke(at: CGPoint(x: 42, y: 42))
        let maskedStroke = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: mask)

        guard let encoded = DittoStrokeModel.encode(maskedStroke),
              let decoded = DittoStrokeModel.decode(from: encoded) else {
            XCTFail("Round-trip encoding/decoding failed")
            return
        }

        XCTAssertNotNil(decoded.mask, "Decoded stroke should have a mask")
        let decodedBounds = decoded.mask!.bounds
        XCTAssertEqual(decodedBounds.origin.x, mask.bounds.origin.x, accuracy: 1)
        XCTAssertEqual(decodedBounds.origin.y, mask.bounds.origin.y, accuracy: 1)
        XCTAssertEqual(decodedBounds.size.width, mask.bounds.size.width, accuracy: 1)
        XCTAssertEqual(decodedBounds.size.height, mask.bounds.size.height, accuracy: 1)
    }

    func testDecodeReturnsNilForInvalidInput() {
        XCTAssertNil(DittoStrokeModel.decode(from: "not valid base64!@#"))
        XCTAssertNil(DittoStrokeModel.decode(from: ""))
        // Valid base64 but not a PKDrawing
        XCTAssertNil(DittoStrokeModel.decode(from: "aGVsbG8="))
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
