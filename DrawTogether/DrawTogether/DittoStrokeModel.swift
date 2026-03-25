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

    /// Encodes a PKStroke as a JSON string (via single-stroke PKDrawing wrapper)
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
    /// ISO8601 with fractional seconds ensures lexicographic sort = chronological order.
    /// PencilKit assigns unique creation dates per stroke, so no additional disambiguation is needed.
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
