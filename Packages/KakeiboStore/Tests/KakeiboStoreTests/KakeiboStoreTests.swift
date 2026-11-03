import Testing
@testable import KakeiboStore

@Test func photosDirectoryNameIsSet() {
    #expect(!KakeiboStore.photosDirectoryName.isEmpty)
}
