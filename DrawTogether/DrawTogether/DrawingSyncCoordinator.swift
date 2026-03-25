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
        syncTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.syncDebounceNanoseconds ?? 0)
            } catch {
                return // Task was cancelled
            }

            // Capture current state on main
            guard let syncContext = await MainActor.run(body: { () -> (strokes: [PKStroke], drawingID: String, ditto: Ditto)? in
                guard let self, !self.isUpdatingFromDitto,
                      let strokes = self.canvasView?.drawing.strokes,
                      let ditto = self.ditto else { return nil }
                return (strokes: strokes, drawingID: self.model.drawingID, ditto: ditto)
            }) else { return }

            // Diff on main (mutates model to persist key mappings)
            let (inserts, removes) = await MainActor.run {
                self?.model.diff(currentStrokes: syncContext.strokes) ?? ([:], [])
            }
            guard !inserts.isEmpty || !removes.isEmpty else { return }

            // Run Ditto transaction off main
            do {
                try await syncContext.ditto.store.transaction { transaction in
                    if !inserts.isEmpty {
                        let doc: [String: Any] = ["_id": syncContext.drawingID, "strokes": inserts]
                        try await transaction.execute(
                            query: "INSERT INTO drawings VALUES (:doc) ON ID CONFLICT DO MERGE",
                            arguments: ["doc": doc]
                        )
                    }

                    for key in removes {
                        try await transaction.execute(
                            query: "UPDATE drawings UNSET strokes.`\(key)` WHERE _id = :drawingID",
                            arguments: ["drawingID": syncContext.drawingID]
                        )
                    }

                    return .commit
                }

                // Apply on main after successful commit
                await MainActor.run { self?.model.apply(inserts: inserts, removes: removes) }
            } catch {
                // Rollback optimistic key mappings so strokes can be re-synced on next diff
                await MainActor.run { self?.model.rollbackPendingKeys(inserts: inserts) }
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

        // Preserve uncommitted local strokes from the canvas (not the binding, which may be stale)
        let knownDates = Set(model.creationDateToKey.keys)
        let currentStrokes = canvasView?.drawing.strokes ?? parent.drawing.strokes
        let uncommittedStrokes = currentStrokes.filter { !knownDates.contains($0.path.creationDate) }

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
