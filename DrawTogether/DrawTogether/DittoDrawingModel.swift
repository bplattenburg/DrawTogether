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

    /// Maps Ditto key (ISO8601+hash) to JSON-encoded single-stroke PKDrawing
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

    /// Compares current canvas strokes against known state using creation dates as stable identifiers.
    /// Returns inserts (key -> JSON string) and removes (keys to UNSET).
    /// Mutating: immediately persists key mappings for new strokes so repeated calls
    /// before apply() won't generate duplicate keys.
    mutating func diff(currentStrokes: [PKStroke]) -> (inserts: [String: String], removes: [String]) {
        let currentDates = Set(currentStrokes.map { $0.path.creationDate })
        let knownDates = Set(creationDateToKey.keys)

        // Strokes in canvas but not known -> new
        var inserts: [String: String] = [:]
        for stroke in currentStrokes where !knownDates.contains(stroke.path.creationDate) {
            guard let encoded = DittoStrokeModel.encode(stroke) else { continue }
            let key = DittoStrokeModel.generateKey(for: stroke.path.creationDate, encodedData: encoded.data)
            inserts[key] = encoded.json
            // Persist key mapping immediately to prevent duplicate inserts on repeated calls
            creationDateToKey[stroke.path.creationDate] = key
            keyToCreationDate[key] = stroke.path.creationDate
        }

        // Strokes known but not in canvas -> removed
        let removes = knownDates.subtracting(currentDates).compactMap { creationDateToKey[$0] }

        return (inserts: inserts, removes: removes)
    }

    // MARK: - Apply Changes

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
