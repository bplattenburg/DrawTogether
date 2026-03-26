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

        guard let json = DittoStrokeModel.encode(originalStroke),
              let roundTrippedStroke = DittoStrokeModel.decode(from: json) else {
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
