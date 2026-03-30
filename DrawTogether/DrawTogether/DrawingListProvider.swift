//
//  DrawingListProvider.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/30/26.
//

import Foundation
import DittoSwift

struct DrawingInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
class DrawingListProvider: ObservableObject {
    @Published var drawings: [DrawingInfo] = []

    private let ditto: Ditto
    private var observer: DittoStoreObserver?

    init(ditto: Ditto = DittoManager.shared.ditto) {
        self.ditto = ditto
        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT _id, name FROM drawings"
            ) { [weak self] result in
                let infos = result.items.compactMap { item -> DrawingInfo? in
                    guard let id = item.value["_id"] as? String else { return nil }
                    let name = item.value["name"] as? String ?? "Untitled"
                    return DrawingInfo(id: id, name: name)
                }
                Task { @MainActor [weak self] in
                    self?.drawings = infos
                }
            }
        } catch {
            NSLog("DrawingListProvider: Failed to register observer: %@", "\(error)")
        }
    }

    func createDrawing(name: String) async throws -> String {
        let id = UUID().uuidString
        let doc: [String: Any] = ["_id": id, "name": name, "strokes": [String: Any]()]
        try await ditto.store.execute(
            query: "INSERT INTO drawings DOCUMENTS (:doc)",
            arguments: ["doc": doc]
        )
        return id
    }

    deinit {
        observer?.cancel()
    }
}
