//
//  CSVExportServiceTests.swift
//  MotionlogTests
//
//  Created by Erick on 26/03/2026.
//

import Testing
import Foundation
@testable import Motionlog

@Suite("CSVExportService")
struct CSVExportServiceTests {

    // MARK: Helpers

    let service = CSVExportService()

    /// A fixed reference date: 2024-01-15 12:00:00 UTC
    let referenceDate = Date(timeIntervalSinceReferenceDate: 726_408_000)

    func makeReading(
        secondsOffset: TimeInterval = 0,
        x: Double = 0, y: Double = 0, z: Double = 0
    ) -> SensorReading {
        SensorReading(
            timestamp: referenceDate.addingTimeInterval(secondsOffset),
            x: x, y: y, z: z
        )
    }

    // MARK: Header

    @Test("CSV always starts with the expected header row")
    func headerRow() {
        let csv = service.generateCSV(from: [])
        let firstLine = csv.components(separatedBy: "\n").first
        #expect(firstLine == "timestamp,x,y,z")
    }

    // MARK: Empty input

    @Test("Empty readings produce a header-only CSV")
    func emptyReadings() {
        let csv = service.generateCSV(from: [])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
    }

    // MARK: Row count

    @Test("One reading produces header + one data row")
    func singleReading() {
        let csv = service.generateCSV(from: [makeReading()])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 2)
    }

    @Test("Multiple readings produce the correct number of rows")
    func multipleReadings() {
        let readings = (0..<10).map { makeReading(secondsOffset: TimeInterval($0)) }
        let csv = service.generateCSV(from: readings)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 11) // header + 10 data rows
    }

    // MARK: Timestamp format

    @Test("Timestamp is ISO 8601 with fractional seconds in UTC")
    func timestampFormat() {
        let csv = service.generateCSV(from: [makeReading()])
        let dataLine = csv.components(separatedBy: "\n")[1]
        let timestamp = dataLine.components(separatedBy: ",")[0]

        // Must match: 2024-01-15T12:00:00.000Z (ISO 8601 + fractional + UTC)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = TimeZone(identifier: "UTC")!

        let parsed = iso.date(from: timestamp)
        #expect(parsed != nil)
        #expect(abs(parsed!.timeIntervalSince(referenceDate)) < 0.001)
    }

    @Test("Timestamp ends with 'Z' (UTC indicator)")
    func timestampEndsWithZ() {
        let csv = service.generateCSV(from: [makeReading()])
        let dataLine = csv.components(separatedBy: "\n")[1]
        let timestamp = dataLine.components(separatedBy: ",")[0]
        #expect(timestamp.hasSuffix("Z"))
    }

    // MARK: Acceleration format

    @Test("Acceleration values are formatted to 6 decimal places")
    func accelerationDecimalPlaces() {
        let reading = makeReading(x: 1.0, y: -0.5, z: 9.80665)
        let csv = service.generateCSV(from: [reading])
        let parts = csv.components(separatedBy: "\n")[1].components(separatedBy: ",")

        // parts[0] = timestamp, parts[1] = x, parts[2] = y, parts[3] = z
        #expect(parts[1] == "1.000000")
        #expect(parts[2] == "-0.500000")
        #expect(parts[3] == "9.806650")
    }

    @Test("Negative acceleration values are preserved correctly")
    func negativeAcceleration() {
        let reading = makeReading(x: -1.234567, y: -0.000001, z: -9.806650)
        let csv = service.generateCSV(from: [reading])
        let parts = csv.components(separatedBy: "\n")[1].components(separatedBy: ",")

        #expect(parts[1] == "-1.234567")
        #expect(parts[2] == "-0.000001")
        #expect(parts[3] == "-9.806650")
    }

    // MARK: Column structure

    @Test("Each data row has exactly 4 comma-separated columns")
    func columnCount() {
        let readings = (0..<5).map {
            makeReading(secondsOffset: TimeInterval($0), x: 0.1, y: 0.2, z: 0.3)
        }
        let csv = service.generateCSV(from: readings)
        let dataLines = csv.components(separatedBy: "\n").dropFirst()
        for line in dataLines where !line.isEmpty {
            #expect(line.components(separatedBy: ",").count == 4)
        }
    }

    // MARK: Ordering

    @Test("Readings appear in the same order they were passed in")
    func rowOrdering() {
        let readings = [
            makeReading(secondsOffset: 0, x: 1),
            makeReading(secondsOffset: 1, x: 2),
            makeReading(secondsOffset: 2, x: 3),
        ]
        let csv = service.generateCSV(from: readings)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        for (index, line) in lines.dropFirst().enumerated() {
            let x = Double(line.components(separatedBy: ",")[1])!
            #expect(x == Double(index + 1))
        }
    }

    // MARK: File export

    @Test("exportToFile creates a file at the returned URL")
    func exportCreatesFile() throws {
        let readings = [makeReading(x: 0.1, y: 0.2, z: 0.3)]
        let url = try service.exportToFile(readings: readings)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("exportToFile writes valid UTF-8 CSV content")
    func exportFileContent() throws {
        let reading = makeReading(x: 1, y: 2, z: 3)
        let url = try service.exportToFile(readings: [reading])
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 2)
        #expect(lines[0] == "timestamp,x,y,z")
    }

    @Test("exportToFile uses a .csv extension")
    func exportFileExtension() throws {
        let url = try service.exportToFile(readings: [])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "csv")
    }
}
