//
//  DittoDrawingModel.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/25/26.
//

import Foundation
import PencilKit

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct DittoDrawingModel {
    let drawingID: String

    /// Maps Ditto key (ISO8601+UUID) to JSON-encoded single-stroke PKDrawing
    private(set) var strokeMap: [String: String] = [:]

    /// Maps stroke creation date to Ditto key, for stable diffing
    private(set) var creationDateToKey: [Date: String] = [:]

    /// Reverse map: Ditto key to creation date, for O(1) removal lookups
    private(set) var keyToCreationDate: [String: Date] = [:]

    init(drawingID: String = "1") {
        self.drawingID = drawingID
    }

    // MARK: - Key Generation

    func generateKey(for date: Date) -> String {
        let timestamp = ISO8601DateFormatter.fractional.string(from: date)
        return "\(timestamp)-\(UUID().uuidString)"
    }

    // MARK: - Drawing Reconstruction

    /// Rebuilds a PKDrawing from strokeMap by sorting keys lexicographically (chronological z-order)
    func drawing() -> PKDrawing {
        let sortedKeys = strokeMap.keys.sorted()
        let strokes: [PKStroke] = sortedKeys.compactMap { key in
            guard let json = strokeMap[key],
                  let data = json.data(using: .utf8) else {
                assertionFailure("Missing or invalid UTF-8 data for stroke key: \(key)")
                return nil
            }
            guard let wrapper = try? JSONDecoder().decode(PKDrawing.self, from: data),
                  let stroke = wrapper.strokes.first else {
                assertionFailure("Failed to decode stroke for key: \(key)")
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
            if let data = json.data(using: .utf8),
               let wrapper = try? JSONDecoder().decode(PKDrawing.self, from: data),
               let stroke = wrapper.strokes.first {
                creationDateToKey[stroke.path.creationDate] = key
                keyToCreationDate[key] = stroke.path.creationDate
            }
        }
    }

    // MARK: - Diffing

    /// Compares current canvas strokes against known state using creation dates as stable identifiers.
    /// Returns inserts (key -> JSON string) and removes (keys to UNSET).
    func diff(currentStrokes: [PKStroke]) -> (inserts: [String: String], removes: [String]) {
        let currentDates = Set(currentStrokes.map { $0.path.creationDate })
        let knownDates = Set(creationDateToKey.keys)

        // Strokes in canvas but not known -> new
        var inserts: [String: String] = [:]
        for stroke in currentStrokes where !knownDates.contains(stroke.path.creationDate) {
            let key = generateKey(for: stroke.path.creationDate)
            let wrapper = PKDrawing(strokes: [stroke])
            if let data = try? JSONEncoder().encode(wrapper),
               let json = String(data: data, encoding: .utf8) {
                inserts[key] = json
            }
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
            if let data = json.data(using: .utf8),
               let wrapper = try? JSONDecoder().decode(PKDrawing.self, from: data),
               let stroke = wrapper.strokes.first {
                creationDateToKey[stroke.path.creationDate] = key
                keyToCreationDate[key] = stroke.path.creationDate
            }
        }
    }
}
