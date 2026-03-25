//
//  DrawingSyncCoordinator.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/25/26.
//

import Foundation
import PencilKit
import DittoSwift

/// Coordinates bidirectional sync between a PKCanvasView and Ditto.
/// Observes local drawing changes, diffs strokes, and syncs to Ditto via transactions.
/// Observes remote Ditto changes and rebuilds the local drawing, preserving uncommitted local strokes.
class DrawingSyncCoordinator: NSObject, PKCanvasViewDelegate {
    var parent: CanvasView
    var toolPicker: PKToolPicker?
    var observer: DittoStoreObserver?
    var model = DittoDrawingModel()
    var isUpdatingFromDitto = false
    weak var canvasView: PKCanvasView?

    /// The Ditto instance used for sync. Injected for testability.
    let ditto: Ditto?

    /// Debounce task for outbound sync — cancelled and recreated on each drawing change
    private var syncTask: Task<Void, Never>?

    /// Debounce interval for coalescing rapid drawing changes
    let syncDebounceNanoseconds: UInt64

    init(_ parent: CanvasView, ditto: Ditto? = DittoManager.shared?.ditto, syncDebounceNanoseconds: UInt64 = 100_000_000) {
        self.parent = parent
        self.ditto = ditto
        self.syncDebounceNanoseconds = syncDebounceNanoseconds
        super.init()
        // Observer filtered by drawingID so .first always matches
        observer = try? ditto?.store.registerObserver(
            query: "SELECT * FROM drawings WHERE _id = :drawingID",
            arguments: ["drawingID": model.drawingID],
            handler: updateFromDitto(_:)
        )
    }

    deinit {
        syncTask?.cancel()
        observer?.cancel()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isUpdatingFromDitto else { return }

        // Cancel any in-flight sync and debounce
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.syncDebounceNanoseconds ?? 0)
            } catch {
                return // Task was cancelled
            }
            guard let self = self, !self.isUpdatingFromDitto else { return }

            // Read current canvas strokes at debounce fire time (not capture time)
            // to ensure we have the latest state including any Ditto updates
            guard let currentStrokes = self.canvasView?.drawing.strokes else { return }

            let (inserts, removes) = self.model.diff(currentStrokes: currentStrokes)
            guard !inserts.isEmpty || !removes.isEmpty else { return }

            let drawingID = self.model.drawingID
            do {
                guard let ditto = self.ditto else { return }

                try await ditto.store.transaction { transaction in
                    // Batch all inserts into a single MERGE operation
                    if !inserts.isEmpty {
                        let doc: [String: Any] = ["_id": drawingID, "strokes": inserts]
                        try await transaction.execute(
                            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
                            arguments: ["doc": doc]
                        )
                    }

                    for key in removes {
                        try await transaction.execute(
                            query: "UPDATE drawings UNSET strokes.`\(key)` WHERE _id = :drawingID",
                            arguments: ["drawingID": drawingID]
                        )
                    }

                    return .commit
                }

                self.model.apply(inserts: inserts, removes: removes)
            } catch {
                NSLog("Error syncing strokes: %@", "\(error)")
            }
        }
    }

    func updateFromDitto(_ result: DittoSwift.DittoQueryResult) {
        // Observer is filtered by drawingID, so .first always matches
        guard let item = result.items.first,
              let rawMap = item.value["strokes"] as? [String: Any] else {
            return
        }

        var strokesMap: [String: String] = [:]
        for (key, value) in rawMap {
            if let strokeString = value as? String {
                strokesMap[key] = strokeString
            }
        }

        // Cancel any pending sync — will be re-triggered if there are uncommitted local strokes
        syncTask?.cancel()

        // Preserve uncommitted local strokes that haven't been synced to Ditto yet
        let knownDates = Set(model.creationDateToKey.keys)
        let uncommittedStrokes = parent.drawing.strokes.filter { !knownDates.contains($0.path.creationDate) }

        model.updateFromStrokesMap(strokesMap)

        // Merge Ditto strokes with any uncommitted local strokes
        var strokes = model.drawing().strokes
        if !uncommittedStrokes.isEmpty {
            strokes.append(contentsOf: uncommittedStrokes)
            strokes.sort { $0.path.creationDate < $1.path.creationDate }
        }

        isUpdatingFromDitto = true
        parent.drawing = PKDrawing(strokes: strokes)
        isUpdatingFromDitto = false
    }
}
