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

    func testEncodeProducesValidJSON() {
        let stroke = makeStroke(at: CGPoint(x: 42, y: 42))
        guard let encoded = DittoStrokeModel.encode(stroke) else {
            XCTFail("Failed to encode stroke")
            return
        }
        XCTAssertFalse(encoded.json.isEmpty)
        XCTAssertFalse(encoded.data.isEmpty)
    }

    func testRoundTripPreservesContent() {
        let originalStroke = makeStroke(at: CGPoint(x: 42, y: 42))

        guard let encoded = DittoStrokeModel.encode(originalStroke),
              let roundTrippedStroke = DittoStrokeModel.decode(from: encoded.json) else {
            XCTFail("Round-trip encoding/decoding failed")
            return
        }

        XCTAssertEqual(roundTrippedStroke.path.count, originalStroke.path.count)
        XCTAssertEqual(roundTrippedStroke.path.first?.location.x ?? 0, 42, accuracy: 1)
        XCTAssertEqual(roundTrippedStroke.path.first?.location.y ?? 0, 42, accuracy: 1)
        XCTAssertEqual(roundTrippedStroke.ink.inkType, originalStroke.ink.inkType)
    }

    func testDecodeReturnsNilForInvalidJSON() {
        XCTAssertNil(DittoStrokeModel.decode(from: "not valid json"))
        XCTAssertNil(DittoStrokeModel.decode(from: "{}"))
    }

    // MARK: - Key Generation Tests

    func testGenerateKeyUniqueness() {
        var keys = Set<String>()
        let baseDate = Date()
        for i in 0..<100 {
            let stroke = makeStroke(at: CGPoint(x: CGFloat(i), y: CGFloat(i)), creationDate: baseDate.addingTimeInterval(Double(i) * 0.001))
            guard let encoded = DittoStrokeModel.encode(stroke) else { continue }
            keys.insert(DittoStrokeModel.generateKey(for: stroke.path.creationDate, encodedData: encoded.data))
        }
        XCTAssertEqual(keys.count, 100, "All 100 generated keys should be unique")
    }

    func testGenerateKeyContainsISO8601Prefix() {
        let date = Date()
        let stroke = makeStroke(creationDate: date)
        guard let encoded = DittoStrokeModel.encode(stroke) else {
            XCTFail("Failed to encode stroke")
            return
        }
        let key = DittoStrokeModel.generateKey(for: date, encodedData: encoded.data)
        let expectedPrefix = ISO8601DateFormatter.fractional.string(from: date)
        XCTAssertTrue(key.hasPrefix(expectedPrefix), "Key should start with ISO8601 timestamp")
    }

    func testGenerateKeyIsDeterministic() {
        let stroke = makeStroke(at: CGPoint(x: 42, y: 42), creationDate: Date(timeIntervalSince1970: 1000))
        guard let encoded = DittoStrokeModel.encode(stroke) else {
            XCTFail("Failed to encode stroke")
            return
        }

        let key1 = DittoStrokeModel.generateKey(for: stroke.path.creationDate, encodedData: encoded.data)
        let key2 = DittoStrokeModel.generateKey(for: stroke.path.creationDate, encodedData: encoded.data)
        XCTAssertEqual(key1, key2, "Same stroke data should always produce the same key")
    }
}
