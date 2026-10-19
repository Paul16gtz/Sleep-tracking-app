import XCTest
@testable import SleepTracker

final class LabelMappingTests: XCTestCase {
    func testMapsOnlyKnownLabels() {
        let mapping = LabelMapping(knownLabels: ["snoring", "speech", "dog"])

        XCTAssertEqual(mapping.type(for: "snoring"), .snoring)
        XCTAssertNil(mapping.type(for: "cough"))
        XCTAssertEqual(mapping.availableTypes, [.snoring, .speech])
    }

    func testEmptyKnownLabelsYieldsEmptyMapping() {
        let mapping = LabelMapping(knownLabels: [])

        XCTAssertTrue(mapping.availableTypes.isEmpty)
        XCTAssertNil(mapping.type(for: "snoring"))
    }

    func testCandidatesCoverAllTypes() {
        for type in SoundEventType.allCases {
            XCTAssertFalse(
                (LabelMapping.candidates[type] ?? []).isEmpty,
                "No candidate labels for \(type.rawValue)"
            )
        }
    }

    func testMakeWindowTakesMaxPerType() {
        let mapping = LabelMapping(knownLabels: ["snoring", "speech"])
        let ranked = [
            RankedLabel(label: "snoring", confidence: 0.7),
            RankedLabel(label: "speech", confidence: 0.2),
            RankedLabel(label: "snoring", confidence: 0.1),
            RankedLabel(label: "dog", confidence: 0.9)
        ]

        let window = ClassificationWindow.make(from: ranked, mapping: mapping, start: 3, end: 4.5)

        XCTAssertEqual(window.confidences, [.snoring: 0.7, .speech: 0.2])
        XCTAssertEqual(window.start, 3)
        XCTAssertEqual(window.end, 4.5)
    }
}
