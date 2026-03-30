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
    var model = DittoDrawingModel() {
        didSet { onModelUpdate?() }
    }
    var isUpdatingFromDitto = false

    /// Optional callback invoked after the model is updated (e.g., after inbound sync).
    /// Used by tests to fulfill expectations without timers or polling.
    var onModelUpdate: (() -> Void)?
    weak var canvasView: PKCanvasView?

    /// The Ditto instance used for sync. Injected for testability.
    let ditto: Ditto

    /// Debounce task for outbound sync — cancelled and recreated on each drawing change
    private var syncTask: Task<Void, Never>?

    /// Debounce interval for coalescing rapid drawing changes
    let syncDebounceNanoseconds: UInt64

    init(_ parent: CanvasView, ditto: Ditto = DittoManager.shared.ditto, syncDebounceNanoseconds: UInt64 = 100_000_000, drawingID: String = "1") {
        self.parent = parent
        self.ditto = ditto
        self.model = DittoDrawingModel(drawingID: drawingID)
        self.syncDebounceNanoseconds = syncDebounceNanoseconds
        super.init()
        // Observer filtered by drawingID so .first always matches
        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM drawings WHERE _id = :drawingID",
                arguments: ["drawingID": drawingID],
                handler: updateFromDitto(_:)
            )
        } catch {
            NSLog("Failed to register Ditto observer for drawingID %@: %@", model.drawingID, "\(error)")
            fatalError("DrawingSyncCoordinator failed to register Ditto observer: \(error)")
        }
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
            guard let syncContext = await MainActor.run(body: { () -> (strokes: [PKStroke], drawingID: String, ditto: Ditto, knownCreationDateToKey: [Date: String])? in
                guard let self, !self.isUpdatingFromDitto,
                      let strokes = self.canvasView?.drawing.strokes else { return nil }
                return (strokes: strokes, drawingID: self.model.drawingID, ditto: self.ditto, knownCreationDateToKey: self.model.creationDateToKey)
            }) else { return }

            // Diff off main — encoding can be CPU-intensive for many strokes
            let (inserts, removes, newMappings) = DittoDrawingModel.computeDiff(
                currentStrokes: syncContext.strokes,
                knownCreationDateToKey: syncContext.knownCreationDateToKey
            )
            guard !inserts.isEmpty || !removes.isEmpty else { return }

            // Persist key mappings on main to prevent duplicate inserts on repeated diffs
            await MainActor.run { self?.model.persistPendingKeys(newMappings) }

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
        // Observer callback may fire on any thread; dispatch to main for UIKit/SwiftUI safety
        let items = result.items
        DispatchQueue.main.async { [weak self] in
            self?.handleDittoUpdate(items: items)
        }
    }

    private func handleDittoUpdate(items: [DittoSwift.DittoQueryResultItem]) {
        // Observer is filtered by drawingID, so .first always matches
        guard let item = items.first,
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

    // MARK: - Drawing Switching

    /// Tears down the current observer and sets up a new one for a different drawing.
    /// Only the observer query changes — the global Ditto subscription remains as-is.
    func switchDrawing(to drawingID: String) {
        syncTask?.cancel()
        observer?.cancel()

        model = DittoDrawingModel(drawingID: drawingID)

        isUpdatingFromDitto = true
        parent.drawing = PKDrawing()
        isUpdatingFromDitto = false

        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM drawings WHERE _id = :drawingID",
                arguments: ["drawingID": drawingID],
                handler: updateFromDitto(_:)
            )
        } catch {
            NSLog("Failed to register observer for drawingID %@: %@", drawingID, "\(error)")
        }
    }
}
