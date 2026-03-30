//
//  DittoStrokeModel.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/25/26.
//

import Foundation
import PencilKit

/// Handles encoding, decoding, and key generation for individual PKStrokes.
/// Each stroke is serialized by wrapping it in a single-stroke PKDrawing and using
/// `dataRepresentation()` (Apple's recommended persistence path), which preserves all stroke
/// properties including masks set by the bitmap eraser.
///
/// Note: encoding is NOT deterministic across PKDrawing instances — re-wrapping the same stroke
/// produces different bytes each time. Callers must store and reuse encoded values rather than
/// re-encoding for comparison. Use `maskFingerprint(for:)` for change detection.
///
/// Keys are ISO8601 timestamps derived from `PKStrokePath.creationDate`, which PencilKit assigns
/// uniquely when a stroke is drawn, giving deterministic and chronologically sortable keys.
struct DittoStrokeModel {

    /// Encodes a PKStroke as a base64 string via `PKDrawing.dataRepresentation()`.
    /// Preserves all stroke properties including masks. NOT deterministic across calls —
    /// store the result and reuse it rather than re-encoding for comparison.
    static func encode(_ stroke: PKStroke) -> String? {
        let wrapper = PKDrawing(strokes: [stroke])
        return wrapper.dataRepresentation().base64EncodedString()
    }

    /// Decodes a PKStroke from a base64-encoded `PKDrawing.dataRepresentation()` string.
    static func decode(from encoded: String) -> PKStroke? {
        guard let data = Data(base64Encoded: encoded),
              let drawing = try? PKDrawing(data: data) else { return nil }
        return drawing.strokes.first
    }

    /// Returns a deterministic fingerprint of a stroke's mask for change detection.
    /// NSKeyedArchiver produces identical output for the same UIBezierPath, making this
    /// safe for equality comparison. Returns nil if the stroke has no mask.
    static func maskFingerprint(for stroke: PKStroke) -> Data? {
        guard let mask = stroke.mask else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: mask, requiringSecureCoding: true)
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
