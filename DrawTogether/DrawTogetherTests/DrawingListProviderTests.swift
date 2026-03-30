//
//  DrawingListProviderTests.swift
//  DrawTogetherTests
//
//  Created by Brian Plattenburg on 3/30/26.
//

import XCTest
import DittoSwift
@testable import DrawTogether

@MainActor
final class DrawingListProviderTests: XCTestCase {

    var ditto: Ditto!
    var provider: DrawingListProvider!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        ditto = try Ditto(identity: .offlinePlayground(appID: "test", siteID: 1), persistenceDirectory: dir)
        try ditto.disableSyncWithV3()
        try await ditto.store.execute(query: "ALTER SYSTEM SET DQL_STRICT_MODE = false")
        provider = DrawingListProvider(ditto: ditto)
    }

    func testListIsEmptyInitially() {
        XCTAssertTrue(provider.drawings.isEmpty)
    }

    func testCreateDrawingInsertsDocument() async throws {
        let id = try await provider.createDrawing(name: "Test Drawing")

        // Query Ditto directly to verify the document exists
        let result = try await ditto.store.execute(
            query: "SELECT * FROM drawings WHERE _id = :id",
            arguments: ["id": id]
        )
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.value["name"] as? String, "Test Drawing")
    }

    func testObserverPicksUpNewDrawings() async throws {
        // Insert a drawing directly into Ditto
        let doc: [String: Any] = ["_id": "test-id", "name": "Remote Drawing", "strokes": [String: Any]()]
        try await ditto.store.execute(
            query: "INSERT INTO drawings DOCUMENTS (:doc)",
            arguments: ["doc": doc]
        )

        // Wait for the observer to pick it up
        let exp = expectation(description: "Provider picks up new drawing")
        let cancellable = provider.$drawings.dropFirst().sink { drawings in
            if drawings.contains(where: { $0.id == "test-id" && $0.name == "Remote Drawing" }) {
                exp.fulfill()
            }
        }
        await fulfillment(of: [exp], timeout: 5.0)
        cancellable.cancel()
    }
}
