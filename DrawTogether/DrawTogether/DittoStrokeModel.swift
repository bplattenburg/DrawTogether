//
//  DittoStrokeModel.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/25/26.
//

import Foundation
import PencilKit
import CryptoKit

/// Handles encoding, decoding, and key generation for individual PKStrokes.
/// Each stroke is serialized by wrapping it in a single-stroke PKDrawing (since PKStroke is not Codable).
/// Keys are ISO8601 timestamps with a content hash suffix for deterministic, sortable identification.
struct DittoStrokeModel {

    /// Encodes a PKStroke as a JSON string (via single-stroke PKDrawing wrapper)
    static func encode(_ stroke: PKStroke) -> (json: String, data: Data)? {
        let wrapper = PKDrawing(strokes: [stroke])
        guard let data = try? JSONEncoder().encode(wrapper),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json: json, data: data)
    }

    /// Decodes a PKStroke from a JSON string (via single-stroke PKDrawing wrapper)
    static func decode(from json: String) -> PKStroke? {
        guard let data = json.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(PKDrawing.self, from: data) else { return nil }
        return wrapper.strokes.first
    }

    /// Generates a deterministic, sortable key from a stroke's creation date and encoded data.
    /// ISO8601 prefix ensures lexicographic sort = chronological order.
    /// SHA256 hash suffix provides uniqueness for strokes with the same creation date.
    static func generateKey(for date: Date, encodedData: Data) -> String {
        let timestamp = ISO8601DateFormatter.fractional.string(from: date)
        let hash = SHA256.hash(data: encodedData)
        let hashString = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "\(timestamp)-\(hashString)"
    }
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
