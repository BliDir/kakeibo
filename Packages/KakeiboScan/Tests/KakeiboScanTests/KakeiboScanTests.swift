import Testing
@testable import KakeiboScan

@Test func japaneseIsFirstRecognitionLanguage() {
    #expect(KakeiboScan.recognitionLanguages.first == "ja-JP")
}
