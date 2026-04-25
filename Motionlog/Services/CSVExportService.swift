//
//  CSVExportService.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import Foundation

// MARK: - CSVExportService

/// Converts an array of `SensorReading` values into a CSV file.
///
/// Intentionally a pure value type with no stored state — every method is
/// a deterministic transformation of its inputs, making it trivially testable.
struct CSVExportService {

    // MARK: Constants

    static let header = "timestamp,x,y,z"

    // MARK: Formatters (static to avoid re-creating on every call)

    /// ISO 8601 formatter with fractional seconds, always in UTC.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")!
        return f
    }()

    // MARK: CSV generation

    /// Builds a CSV string from the given readings.
    ///
    /// - Parameter readings: The samples to serialise. May be empty — the
    ///   result will contain only the header row.
    /// - Returns: A UTF-8 string with a header row followed by one data row
    ///   per reading.  Acceleration values are formatted to 6 decimal places.
    func generateCSV(from readings: [SensorReading]) -> String {
        var lines: [String] = [Self.header]

        for reading in readings {
            let ts = Self.timestampFormatter.string(from: reading.timestamp)
            let row = "\(ts),\(format(reading.x)),\(format(reading.y)),\(format(reading.z))"
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: File export

    /// Writes the CSV to a temporary file and returns its `URL`.
    ///
    /// The file is placed in the system's temporary directory with a name
    /// derived from the current date so multiple exports don't collide.
    /// The caller is responsible for deleting the file when done (e.g. after
    /// the share sheet is dismissed).
    ///
    /// - Parameter readings: The samples to export.
    /// - Returns: A file `URL` pointing to the written CSV.
    /// - Throws: Any `Error` raised by `FileManager` or `String.write`.
    func exportToFile(readings: [SensorReading]) throws -> URL {
        let csv = generateCSV(from: readings)

        let filename = "motionlog-\(filenameDateStamp()).csv"
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(filename)

        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Private helpers

    /// Formats a `Double` to exactly 6 decimal places.
    private func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    /// Returns a compact date string suitable for use in a filename.
    private func filenameDateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.string(from: Date())
    }
}
