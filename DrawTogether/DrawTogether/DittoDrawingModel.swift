//
//  DittoDrawingModel.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/25/26.
//

import Foundation
import PencilKit

/// Manages the sync state for a single drawing document in Ditto.
/// Tracks which strokes are known (synced) and provides diffing to detect local changes.
struct DittoDrawingModel {
    let drawingID: String

    /// Maps Ditto key (ISO8601 timestamp string) to JSON-encoded single-stroke PKDrawing
    private(set) var strokeMap: [String: String] = [:]

    /// Maps stroke creation date to Ditto key, for stable diffing
    private(set) var creationDateToKey: [Date: String] = [:]

    /// Reverse map: Ditto key to creation date, for O(1) removal lookups
    private(set) var keyToCreationDate: [String: Date] = [:]

    init(drawingID: String = "1") {
        self.drawingID = drawingID
    }

    // MARK: - Drawing Reconstruction

    /// Rebuilds a PKDrawing from strokeMap by sorting keys lexicographically (chronological z-order)
    func drawing() -> PKDrawing {
        let sortedKeys = strokeMap.keys.sorted()
        let strokes: [PKStroke] = sortedKeys.compactMap { key in
            guard let json = strokeMap[key] else {
                NSLog("DittoDrawingModel.drawing(): Missing data for stroke key: %@", key)
                return nil
            }
            guard let stroke = DittoStrokeModel.decode(from: json) else {
                NSLog("DittoDrawingModel.drawing(): Failed to decode stroke for key: %@", key)
                return nil
            }
            return stroke
        }
        return PKDrawing(strokes: strokes)
    }

    // MARK: - Stroke Map Update

    /// Updates from a raw strokes dictionary parsed from a Ditto result
    mutating func updateFromStrokesMap(_ map: [String: String]) {
        strokeMap = map
        creationDateToKey = [:]
        keyToCreationDate = [:]
        for (key, json) in map {
            if let stroke = DittoStrokeModel.decode(from: json) {
                creationDateToKey[stroke.path.creationDate] = key
                keyToCreationDate[key] = stroke.path.creationDate
            }
        }
    }

    // MARK: - Diffing

    /// Compares current canvas strokes against a snapshot of known state using creation dates as
    /// stable identifiers. Returns inserts (key -> JSON string) and removes (keys to UNSET).
    ///
    /// This is a pure function that can run off the main thread — it takes a snapshot of known
    /// dates/keys rather than reading from `self`. The caller is responsible for persisting the
    /// returned key mappings via `persistPendingKeys`.
    ///
    /// Strokes are identified by `PKStrokePath.creationDate`, which PencilKit assigns uniquely when
    /// a stroke is drawn. This only detects new and removed strokes — in-place modifications to
    /// existing strokes (same creationDate, different content) are not detected.
    ///
    /// Known limitation: the bitmap eraser sets a `mask` on existing strokes without changing their
    /// creationDate, so eraser changes are not synced. The vector eraser works correctly because it
    /// removes/splits strokes, producing new creationDates. See: https://github.com/bplattenburg/DrawTogether/issues/8
    static func computeDiff(
        currentStrokes: [PKStroke],
        knownCreationDateToKey: [Date: String]
    ) -> (inserts: [String: String], removes: [String], newMappings: [(date: Date, key: String)]) {
        let currentDates = Set(currentStrokes.map { $0.path.creationDate })
        let knownDates = Set(knownCreationDateToKey.keys)

        // Strokes in canvas but not known -> new
        var inserts: [String: String] = [:]
        var newMappings: [(date: Date, key: String)] = []
        for stroke in currentStrokes where !knownDates.contains(stroke.path.creationDate) {
            guard let json = DittoStrokeModel.encode(stroke) else { continue }
            let key = DittoStrokeModel.generateKey(for: stroke.path.creationDate)
            inserts[key] = json
            newMappings.append((date: stroke.path.creationDate, key: key))
        }

        // Strokes known but not in canvas -> removed
        let removes = knownDates.subtracting(currentDates).compactMap { knownCreationDateToKey[$0] }

        return (inserts: inserts, removes: removes, newMappings: newMappings)
    }

    /// Persists key mappings from a `computeDiff` result so repeated diffs won't generate duplicates.
    mutating func persistPendingKeys(_ mappings: [(date: Date, key: String)]) {
        for mapping in mappings {
            creationDateToKey[mapping.date] = mapping.key
            keyToCreationDate[mapping.key] = mapping.date
        }
    }

    // MARK: - Apply Changes

    /// Rolls back key mappings that were optimistically persisted by diff() when a transaction fails.
    /// This allows the strokes to be re-detected and re-synced on the next diff.
    mutating func rollbackPendingKeys(inserts: [String: String]) {
        for key in inserts.keys {
            if let date = keyToCreationDate[key] {
                creationDateToKey.removeValue(forKey: date)
                keyToCreationDate.removeValue(forKey: key)
            }
        }
    }

    /// Updates internal state after a diff has been synced to Ditto
    mutating func apply(inserts: [String: String], removes: [String]) {
        for key in removes {
            if let date = keyToCreationDate[key] {
                creationDateToKey.removeValue(forKey: date)
                keyToCreationDate.removeValue(forKey: key)
            }
            strokeMap.removeValue(forKey: key)
        }
        for (key, json) in inserts {
            strokeMap[key] = json
            if let stroke = DittoStrokeModel.decode(from: json) {
                creationDateToKey[stroke.path.creationDate] = key
                keyToCreationDate[key] = stroke.path.creationDate
            }
        }
    }
}
