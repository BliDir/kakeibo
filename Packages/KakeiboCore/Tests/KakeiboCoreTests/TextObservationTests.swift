import Foundation
import Testing
import KakeiboCore

@Suite struct TextObservationTests {
    @Test func convertsBottomLeftToTopLeft() {
        // A line near the bottom of the page in Vision terms (y = 0.1 from the bottom).
        let box = BoundingBox.fromBottomLeft(x: 0.2, y: 0.1, width: 0.5, height: 0.05)
        #expect(box.x == 0.2)
        #expect(abs(box.y - 0.85) < 1e-9)   // 1 - 0.1 - 0.05
        #expect(abs(box.maxY - 0.9) < 1e-9)
        #expect(box.width == 0.5)
        #expect(box.height == 0.05)
    }

    @Test func topOfPageStaysAtTop() {
        let box = BoundingBox.fromBottomLeft(x: 0, y: 0.95, width: 1, height: 0.05)
        #expect(abs(box.y) < 1e-9)
    }

    @Test func edgesAndMidpoints() {
        let box = BoundingBox(x: 0.1, y: 0.2, width: 0.4, height: 0.1)
        #expect(abs(box.maxX - 0.5) < 1e-9)
        #expect(abs(box.midX - 0.3) < 1e-9)
        #expect(abs(box.maxY - 0.3) < 1e-9)
        #expect(abs(box.midY - 0.25) < 1e-9)
    }

    @Test func codableRoundTrip() throws {
        let observation = TextObservation(
            text: "合計 ¥1,076",
            boundingBox: BoundingBox(x: 0.1, y: 0.6, width: 0.8, height: 0.03),
            confidence: 0.92
        )
        let data = try JSONEncoder().encode([observation])
        #expect(try JSONDecoder().decode([TextObservation].self, from: data) == [observation])
    }
}
