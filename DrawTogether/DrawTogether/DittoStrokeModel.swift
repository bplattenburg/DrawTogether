//
//  DittoStrokeModel.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/25/26.
//

import Foundation
import PencilKit

/// Handles encoding, decoding, and key generation for individual PKStrokes.
/// Each stroke is serialized by wrapping it in a single-stroke PKDrawing (since PKStroke is not Codable).
/// Keys are ISO8601 timestamps derived from `PKStrokePath.creationDate`, which PencilKit assigns
/// uniquely when a stroke is drawn, giving deterministic and chronologically sortable keys.
struct DittoStrokeModel {

    /// Encodes a PKStroke as a JSON string (via single-stroke PKDrawing wrapper).
    /// Note: JSON encoding via PKDrawing's Codable conformance may not preserve the `mask` property
    /// set by the bitmap eraser. The official persistence path is `PKDrawing.dataRepresentation()`.
    /// See: https://github.com/bplattenburg/DrawTogether/issues/8
    static func encode(_ stroke: PKStroke) -> String? {
        let wrapper = PKDrawing(strokes: [stroke])
        guard let data = try? JSONEncoder().encode(wrapper) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes a PKStroke from a JSON string (via single-stroke PKDrawing wrapper)
    static func decode(from json: String) -> PKStroke? {
        guard let data = json.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(PKDrawing.self, from: data) else { return nil }
        return wrapper.strokes.first
    }

    /// Generates a deterministic, sortable key from a stroke's creation date.
    /// ISO8601 with fractional seconds (millisecond precision) ensures lexicographic sort = chronological order.
    /// Collisions require two strokes created within the same millisecond, which is practically impossible:
    /// each stroke requires physical drawing input that far exceeds 1ms, and PencilKit serializes stroke
    /// creation on the main thread. Cross-device collisions at the same millisecond would merge via
    /// Ditto's MAP CRDT (last-write-wins per key), not cause data loss.
    static func generateKey(for date: Date) -> String {
        ISO8601DateFormatter.fractional.string(from: date)
    }
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
