#if canImport(Security)
    import Testing

    @testable import WaiveraAPI

    struct KeychainGroupTests {
        @Test func signedBuildSharesTheSession() {
            let info: [String: Any] = [KeychainTokenStore.accessGroupKey: "AB12CD34EF.com.waivera.waivera.shared"]
            #expect(KeychainTokenStore.sharedAccessGroup(info: info) == "AB12CD34EF.com.waivera.waivera.shared")
        }

        @Test func buildWithoutATeamKeepsTheSessionPrivate() {
            let unusable = [
                ".com.waivera.waivera.shared", "$(DEVELOPMENT_TEAM).com.waivera.waivera.shared", "ab12cd34ef.x", "",
            ]
            for value in unusable {
                #expect(KeychainTokenStore.sharedAccessGroup(info: [KeychainTokenStore.accessGroupKey: value]) == nil)
            }
            #expect(KeychainTokenStore.sharedAccessGroup(info: nil) == nil)
        }
    }
#endif
