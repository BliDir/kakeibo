import Testing
@testable import KakeiboCore

@Test func timeZoneIsTokyo() {
    #expect(KakeiboCore.timeZone.identifier == "Asia/Tokyo")
}
