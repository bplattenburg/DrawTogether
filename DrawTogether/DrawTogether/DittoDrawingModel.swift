//
//  DittoDrawingModel.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/25/26.
//

import Foundation
import PencilKit

/// Manages the sync state for a single drawing document in Ditto.
/// Tracks which strokes are known (synced) and builds the desired state for outbound sync.
struct DittoDrawingModel {
    let drawingID: String

    /// Maps Ditto key (ISO8601 timestamp string) to encoded PKDrawing (may contain multiple strokes)
    private(set) var strokeMap: [String: String] = [:]

    /// Maps stroke creation date to Ditto key, for key reuse and remove detection
    private(set) var creationDateToKey: [Date: String] = [:]

    /// Reverse map: Ditto key to creation date, for O(1) removal lookups
    private(set) var keyToCreationDate: [String: Date] = [:]

    /// Group fingerprints for known stroke groups, used to detect bitmap eraser modifications
    /// (mask changes and stroke splits). Key is the Ditto key; value is a composite fingerprint
    /// encoding stroke count and each stroke's mask data.
    private(set) var groupFingerprints: [String: Data] = [:]

    init(drawingID: String = "1") {
        self.drawingID = drawingID
    }

    // MARK: - Drawing Reconstruction

    /// Rebuilds a PKDrawing from strokeMap by sorting keys lexicographically (chronological z-order).
    /// Each key may contain multiple strokes (split pieces), which are flattened in order.
    func drawing() -> PKDrawing {
        let sortedKeys = strokeMap.keys.sorted()
        let strokes: [PKStroke] = sortedKeys.flatMap { key -> [PKStroke] in
            guard let encoded = strokeMap[key] else {
                NSLog("DittoDrawingModel.drawing(): Missing data for stroke key: %@", key)
                return []
            }
            let decoded = DittoStrokeModel.decodeGroup(from: encoded)
            if decoded.isEmpty {
                NSLog("DittoDrawingModel.drawing(): Failed to decode stroke(s) for key: %@", key)
            }
            return decoded
        }
        return PKDrawing(strokes: strokes)
    }

    // MARK: - Stroke Map Update

    /// Updates from a raw strokes dictionary parsed from a Ditto result
    mutating func updateFromStrokesMap(_ map: [String: String]) {
        strokeMap = map
        creationDateToKey = [:]
        keyToCreationDate = [:]
        groupFingerprints = [:]
        for (key, encoded) in map {
            let strokes = DittoStrokeModel.decodeGroup(from: encoded)
            if let first = strokes.first {
                creationDateToKey[first.path.creationDate] = key
                keyToCreationDate[key] = first.path.creationDate
                groupFingerprints[key] = DittoStrokeModel.groupFingerprint(for: strokes)
            }
        }
    }

    // MARK: - Build Desired State

    /// Builds the full desired strokes map from current canvas strokes.
    ///
    /// Groups strokes by `creationDate` to handle bitmap eraser splits and the rare case of
    /// unrelated strokes sharing a timestamp. All strokes in a group are encoded together as a
    /// multi-stroke PKDrawing under one Ditto key, so no data is lost on collision.
    ///
    /// For known groups whose fingerprint hasn't changed, reuses the stored encoding
    /// (PKDrawing encoding is non-deterministic across instances, so re-encoding would produce
    /// different bytes and cause unnecessary Ditto replication or concurrent write conflicts).
    /// For new groups or groups with fingerprint changes (mask change, split, or piece
    /// deletion), encodes fresh.
    ///
    /// Also detects removes: known keys not present on the canvas.
    ///
    /// This is a pure function that can run off the main thread.
    static func buildDesiredState(
        currentStrokes: [PKStroke],
        knownCreationDateToKey: [Date: String],
        knownStrokeMap: [String: String],
        knownGroupFingerprints: [String: Data]
    ) -> (desired: [String: String], removes: [String], newMappings: [(date: Date, key: String)]) {
        var desired: [String: String] = [:]
        var newMappings: [(date: Date, key: String)] = []

        // Group strokes by creationDate, preserving z-order within each group
        var strokesByDate: [(date: Date, strokes: [PKStroke])] = []
        var dateIndex: [Date: Int] = [:]
        for stroke in currentStrokes {
            let date = stroke.path.creationDate
            if let idx = dateIndex[date] {
                strokesByDate[idx].strokes.append(stroke)
            } else {
                dateIndex[date] = strokesByDate.count
                strokesByDate.append((date: date, strokes: [stroke]))
            }
        }

        for (date, group) in strokesByDate {
            if let existingKey = knownCreationDateToKey[date] {
                // Known group — check if fingerprint changed (mask change or split)
                let currentFP = DittoStrokeModel.groupFingerprint(for: group)
                let storedFP = knownGroupFingerprints[existingKey]
                if currentFP == storedFP, let storedEncoding = knownStrokeMap[existingKey] {
                    // Group unchanged — reuse stored encoding
                    desired[existingKey] = storedEncoding
                } else {
                    // Group changed (mask change, split, or piece deletion) — re-encode
                    guard let encoded = DittoStrokeModel.encodeGroup(group) else { continue }
                    desired[existingKey] = encoded
                }
            } else {
                // New stroke group
                guard let encoded = DittoStrokeModel.encodeGroup(group) else { continue }
                let key = DittoStrokeModel.generateKey(for: date)
                desired[key] = encoded
                newMappings.append((date: date, key: key))
            }
        }

        // Keys known locally but not on canvas → removes
        let currentKeys = Set(desired.keys)
        let knownKeys = Set(knownCreationDateToKey.values)
        let removes = Array(knownKeys.subtracting(currentKeys))

        return (desired: desired, removes: removes, newMappings: newMappings)
    }

    // MARK: - Pending State Management

    /// Persists key mappings and stroke data from a buildDesiredState result so repeated
    /// calls won't generate duplicates or re-detect the same changes.
    /// Returns old strokeMap values for rollback on transaction failure.
    mutating func persistPending(
        newMappings: [(date: Date, key: String)],
        desired: [String: String],
        currentStrokes: [PKStroke]
    ) -> [String: String?] {
        // Track new key mappings
        for mapping in newMappings {
            creationDateToKey[mapping.date] = mapping.key
            keyToCreationDate[mapping.key] = mapping.date
        }

        // Update strokeMap and capture old values for rollback
        var oldValues: [String: String?] = [:]
        for (key, encoded) in desired {
            oldValues[key] = strokeMap[key]
            strokeMap[key] = encoded
        }

        // Update group fingerprints from current strokes grouped by date
        var strokesByDate: [Date: [PKStroke]] = [:]
        for stroke in currentStrokes {
            strokesByDate[stroke.path.creationDate, default: []].append(stroke)
        }
        for (date, group) in strokesByDate {
            if let key = creationDateToKey[date] {
                groupFingerprints[key] = DittoStrokeModel.groupFingerprint(for: group)
            }
        }

        return oldValues
    }

    /// Rolls back changes from persistPending when a transaction fails.
    mutating func rollbackPending(
        oldValues: [String: String?],
        newMappings: [(date: Date, key: String)]
    ) {
        // Remove new key mappings
        for mapping in newMappings {
            creationDateToKey.removeValue(forKey: mapping.date)
            keyToCreationDate.removeValue(forKey: mapping.key)
        }

        // Restore old strokeMap values and recalculate group fingerprints
        for (key, oldValue) in oldValues {
            if let old = oldValue {
                strokeMap[key] = old
                let strokes = DittoStrokeModel.decodeGroup(from: old)
                if !strokes.isEmpty {
                    groupFingerprints[key] = DittoStrokeModel.groupFingerprint(for: strokes)
                } else {
                    groupFingerprints.removeValue(forKey: key)
                }
            } else {
                strokeMap.removeValue(forKey: key)
                groupFingerprints.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Apply Changes

    /// Removes keys from internal state after successful UNSET in Ditto.
    mutating func applyRemoves(_ removes: [String]) {
        for key in removes {
            if let date = keyToCreationDate[key] {
                creationDateToKey.removeValue(forKey: date)
                keyToCreationDate.removeValue(forKey: key)
            }
            strokeMap.removeValue(forKey: key)
            groupFingerprints.removeValue(forKey: key)
        }
    }
}
