//
//  DittoStrokeModel.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/25/26.
//

import Foundation
import PencilKit

/// Handles encoding, decoding, and key generation for PKStroke groups.
/// Strokes are serialized as PKDrawings via `dataRepresentation()` (Apple's recommended
/// persistence path), which preserves all stroke properties including masks set by the bitmap
/// eraser. Multiple strokes sharing a `creationDate` (e.g., bitmap eraser splits or rare
/// timestamp collisions) are packed into a single multi-stroke PKDrawing under one key.
///
/// Note: encoding is NOT deterministic across PKDrawing instances — re-encoding the same
/// strokes produces different bytes each time. Callers must store and reuse encoded values
/// rather than re-encoding for comparison. Use `groupFingerprint(for:)` for change detection.
///
/// Keys are ISO8601 timestamps derived from `PKStrokePath.creationDate`, which PencilKit assigns
/// uniquely when a stroke is drawn, giving deterministic and chronologically sortable keys.
struct DittoStrokeModel {

    /// Encodes a PKStroke as a base64 string via `PKDrawing.dataRepresentation()`.
    /// Preserves all stroke properties including masks. NOT deterministic across calls —
    /// store the result and reuse it rather than re-encoding for comparison.
    static func encode(_ stroke: PKStroke) -> String? {
        encodeGroup([stroke])
    }

    /// Encodes multiple PKStrokes (e.g., split pieces sharing a `creationDate`) as a single
    /// base64-encoded PKDrawing. Preserves stroke order, which determines z-order on decode.
    static func encodeGroup(_ strokes: [PKStroke]) -> String? {
        guard !strokes.isEmpty else { return nil }
        let wrapper = PKDrawing(strokes: strokes)
        return wrapper.dataRepresentation().base64EncodedString()
    }

    /// Decodes all PKStrokes from a base64-encoded `PKDrawing.dataRepresentation()` string.
    /// Returns an empty array on failure. A single-stroke encoding returns a 1-element array.
    static func decodeGroup(from encoded: String) -> [PKStroke] {
        guard let data = Data(base64Encoded: encoded),
              let drawing = try? PKDrawing(data: data) else { return [] }
        return drawing.strokes
    }

    /// Returns a deterministic fingerprint of a stroke's mask for change detection.
    /// NSKeyedArchiver produces identical output for the same UIBezierPath, making this
    /// safe for equality comparison. Returns nil if the stroke has no mask.
    static func maskFingerprint(for stroke: PKStroke) -> Data? {
        guard let mask = stroke.mask else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: mask, requiringSecureCoding: true)
    }

    /// Returns a deterministic fingerprint for a group of strokes (e.g., split pieces).
    /// Captures stroke count and each stroke's mask, so any split, mask change, or piece
    /// deletion is detected. Returns stable bytes for unchanged groups.
    static func groupFingerprint(for strokes: [PKStroke]) -> Data {
        var data = Data()
        var count = UInt32(strokes.count)
        data.append(Data(bytes: &count, count: 4))
        for stroke in strokes {
            if let maskFP = maskFingerprint(for: stroke) {
                var len = UInt32(maskFP.count)
                data.append(Data(bytes: &len, count: 4))
                data.append(maskFP)
            } else {
                var zero = UInt32(0)
                data.append(Data(bytes: &zero, count: 4))
            }
        }
        return data
    }

    /// Generates a deterministic, sortable key from a stroke's creation date.
    /// ISO8601 with fractional seconds (millisecond precision) ensures lexicographic sort = chronological order.
    /// Collisions require two strokes created within the same millisecond, which is practically impossible:
    /// each stroke requires physical drawing input that far exceeds 1ms, and PencilKit serializes stroke
    /// creation on the main thread. If a collision does occur (or PencilKit produces multiple strokes with
    /// the same `creationDate`, e.g., bitmap eraser splits), the strokes are grouped and encoded together
    /// under one key via `encodeGroup`, so no data is lost.
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
