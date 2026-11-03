import Foundation
import Testing
@testable import KakeiboCore

/// Runs `ReceiptParser` over every fixture in `Tests/Fixtures/receipts/` and reports per-field accuracy.
///
/// Fixture format:
/// - `<name>.txt`: OCR text, one receipt row per line.
/// - `<name>.expected.json`: expected fields. A field left out is not scored;
///   a field set to `null` is scored and expects nothing to be found.
///   Optional `scannedOn` (`yyyy-MM-dd`) is the scan date; it defaults to `dayKey`.
@Suite struct ReceiptAccuracyTests {
    /// The M1 gate. Never lower this to make a change pass; fix the parser instead.
    static let minimumTotalAccuracy = 0.90

    /// Scored fields, in report order: (JSON key, label).
    static let fields: [(key: String, label: String)] = [
        ("storeName", "store"),
        ("dayKey", "date"),
        ("time", "time"),
        ("totalYen", "total"),
        ("tax10Yen", "tax10"),
        ("tax8Yen", "tax8"),
        ("payment", "payment"),
        ("invoiceNumber", "invoice"),
        ("category", "category"),
    ]

    @Test func fixtureAccuracy() throws {
        let fixtures = try Fixture.loadAll()
        try #require(!fixtures.isEmpty, "No fixtures found in the test bundle")

        var scored: [String: Int] = [:]
        var correct: [String: Int] = [:]
        var misses: [String] = []

        for fixture in fixtures {
            let draft = ReceiptParser.parse(text: fixture.text, today: fixture.scannedOn)
            let actual = Self.values(of: draft)
            for (key, label) in Self.fields {
                guard let expected = fixture.expected[key] else { continue }
                scored[key, default: 0] += 1
                let got = actual[key] ?? nil
                if Self.matches(expected, got) {
                    correct[key, default: 0] += 1
                } else {
                    misses.append("  \(fixture.name): \(label) expected \(Self.describe(expected)), got \(Self.describe(got))")
                }
            }
        }

        print(Self.report(fixtureCount: fixtures.count, scored: scored, correct: correct, misses: misses))

        let totalScored = scored["totalYen", default: 0]
        try #require(totalScored > 0, "No fixture scores totalYen")
        let totalAccuracy = Double(correct["totalYen", default: 0]) / Double(totalScored)
        #expect(
            totalAccuracy >= Self.minimumTotalAccuracy,
            "Total accuracy \(Self.percent(totalAccuracy)) is below \(Self.percent(Self.minimumTotalAccuracy))"
        )
    }

    @Test func everyFixtureHasExpectedJSON() throws {
        let directory = try Fixture.directory()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for txt in names where txt.hasSuffix(".txt") {
            let json = txt.dropLast(4) + ".expected.json"
            #expect(names.contains(String(json)), "\(txt) has no \(json)")
        }
    }

    // MARK: - Comparing

    /// The draft's scored fields as JSON-like values.
    static func values(of draft: ReceiptDraft) -> [String: Any?] {
        [
            "storeName": draft.storeName,
            "dayKey": draft.dayKey,
            "time": draft.time,
            "totalYen": draft.totalYen,
            "tax10Yen": draft.tax10Yen,
            "tax8Yen": draft.tax8Yen,
            "payment": draft.payment?.rawValue,
            "invoiceNumber": draft.invoiceNumber,
            "category": draft.category?.rawValue,
        ]
    }

    static func matches(_ expected: Any, _ actual: Any?) -> Bool {
        switch (expected, actual) {
        case (is NSNull, nil): true
        case (is NSNull, _), (_, nil): false
        case let (e as String, a as String): e == a
        case let (e as NSNumber, a as Int): e.intValue == a
        default: false
        }
    }

    static func describe(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: "nothing"
        case let s as String: "\"\(s)\""
        case let v?: "\(v)"
        }
    }

    // MARK: - Report

    static func report(fixtureCount: Int, scored: [String: Int], correct: [String: Int], misses: [String]) -> String {
        var lines = ["", "Receipt parser accuracy (\(fixtureCount) fixtures)", ""]
        lines.append("field       correct  scored  accuracy")
        for (key, label) in fields {
            let s = scored[key, default: 0]
            let c = correct[key, default: 0]
            let accuracy = s == 0 ? "-" : percent(Double(c) / Double(s))
            lines.append(
                label.padding(toLength: 12, withPad: " ", startingAt: 0)
                    + String(c).leftPadded(7) + String(s).leftPadded(8) + accuracy.leftPadded(10)
            )
        }
        if !misses.isEmpty {
            lines.append("")
            lines.append("Misses:")
            lines.append(contentsOf: misses)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}

// MARK: - Fixtures

struct Fixture {
    var name: String
    var text: String
    var expected: [String: Any]
    var scannedOn: Date

    static func directory() throws -> URL {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures", withExtension: nil),
            "Fixtures folder missing from the test bundle"
        )
        return url.appendingPathComponent("receipts", isDirectory: true)
    }

    static func loadAll() throws -> [Fixture] {
        let directory = try directory()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".txt") }
            .sorted()
        return try names.map { file in
            let name = String(file.dropLast(4))
            let text = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            let jsonURL = directory.appendingPathComponent(name + ".expected.json")
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL))
            let expected = try #require(object as? [String: Any], "\(name).expected.json is not an object")
            let scanDay = (expected["scannedOn"] as? String) ?? (expected["dayKey"] as? String) ?? "2026-11-03"
            return Fixture(name: name, text: text, expected: expected, scannedOn: try noonInTokyo(scanDay))
        }
    }

    /// 12:00 Asia/Tokyo on a `yyyy-MM-dd` day.
    static func noonInTokyo(_ dayKey: String) throws -> Date {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        try #require(parts.count == 3, "Bad date \(dayKey)")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = KakeiboCore.timeZone
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        return try #require(calendar.date(from: components))
    }
}

private extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
