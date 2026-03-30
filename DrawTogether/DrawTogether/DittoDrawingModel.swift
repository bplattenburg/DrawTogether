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

    /// Maps Ditto key (ISO8601 timestamp string) to encoded single-stroke PKDrawing
    private(set) var strokeMap: [String: String] = [:]

    /// Maps stroke creation date to Ditto key, for key reuse and remove detection
    private(set) var creationDateToKey: [Date: String] = [:]

    /// Reverse map: Ditto key to creation date, for O(1) removal lookups
    private(set) var keyToCreationDate: [String: Date] = [:]

    /// Mask fingerprints for known strokes, used to detect bitmap eraser modifications.
    /// Key is the Ditto key; value is NSKeyedArchiver data of the UIBezierPath mask.
    /// Absent entry means the stroke has no mask.
    private(set) var maskFingerprints: [String: Data] = [:]

    init(drawingID: String = "1") {
        self.drawingID = drawingID
    }

    // MARK: - Drawing Reconstruction

    /// Rebuilds a PKDrawing from strokeMap by sorting keys lexicographically (chronological z-order)
    func drawing() -> PKDrawing {
        let sortedKeys = strokeMap.keys.sorted()
        let strokes: [PKStroke] = sortedKeys.compactMap { key in
            guard let encoded = strokeMap[key] else {
                NSLog("DittoDrawingModel.drawing(): Missing data for stroke key: %@", key)
                return nil
            }
            guard let stroke = DittoStrokeModel.decode(from: encoded) else {
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
        maskFingerprints = [:]
        for (key, encoded) in map {
            if let stroke = DittoStrokeModel.decode(from: encoded) {
                creationDateToKey[stroke.path.creationDate] = key
                keyToCreationDate[key] = stroke.path.creationDate
                if let fp = DittoStrokeModel.maskFingerprint(for: stroke) {
                    maskFingerprints[key] = fp
                }
            }
        }
    }

    // MARK: - Build Desired State

    /// Builds the full desired strokes map from current canvas strokes.
    ///
    /// For known strokes whose mask hasn't changed, reuses the stored encoding from `knownStrokeMap`
    /// (PKDrawing encoding is non-deterministic across instances, so re-encoding would produce
    /// different bytes and cause unnecessary Ditto replication or concurrent write conflicts).
    /// For new strokes or strokes with mask changes, encodes fresh.
    ///
    /// Also detects removes: known keys not present on the canvas.
    ///
    /// This is a pure function that can run off the main thread.
    static func buildDesiredState(
        currentStrokes: [PKStroke],
        knownCreationDateToKey: [Date: String],
        knownStrokeMap: [String: String],
        knownMaskFingerprints: [String: Data]
    ) -> (desired: [String: String], removes: [String], newMappings: [(date: Date, key: String)]) {
        var desired: [String: String] = [:]
        var newMappings: [(date: Date, key: String)] = []

        for stroke in currentStrokes {
            if let existingKey = knownCreationDateToKey[stroke.path.creationDate] {
                // Known stroke — check if mask changed via deterministic fingerprint
                let currentFP = DittoStrokeModel.maskFingerprint(for: stroke)
                let storedFP = knownMaskFingerprints[existingKey]
                if currentFP == storedFP, let storedEncoding = knownStrokeMap[existingKey] {
                    // Mask unchanged — reuse stored encoding to avoid non-deterministic re-encoding
                    desired[existingKey] = storedEncoding
                } else {
                    // Mask changed — re-encode
                    guard let encoded = DittoStrokeModel.encode(stroke) else { continue }
                    desired[existingKey] = encoded
                }
            } else {
                // New stroke
                guard let encoded = DittoStrokeModel.encode(stroke) else { continue }
                let key = DittoStrokeModel.generateKey(for: stroke.path.creationDate)
                desired[key] = encoded
                newMappings.append((date: stroke.path.creationDate, key: key))
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

        // Update mask fingerprints from current strokes
        for stroke in currentStrokes {
            if let key = creationDateToKey[stroke.path.creationDate] {
                if let fp = DittoStrokeModel.maskFingerprint(for: stroke) {
                    maskFingerprints[key] = fp
                } else {
                    maskFingerprints.removeValue(forKey: key)
                }
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

        // Restore old strokeMap values and recalculate fingerprints
        for (key, oldValue) in oldValues {
            if let old = oldValue {
                strokeMap[key] = old
                if let stroke = DittoStrokeModel.decode(from: old) {
                    if let fp = DittoStrokeModel.maskFingerprint(for: stroke) {
                        maskFingerprints[key] = fp
                    } else {
                        maskFingerprints.removeValue(forKey: key)
                    }
                }
            } else {
                strokeMap.removeValue(forKey: key)
                maskFingerprints.removeValue(forKey: key)
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
            maskFingerprints.removeValue(forKey: key)
        }
    }
}
