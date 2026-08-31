import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case .expectation(let message):
            return message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure.expectation(message)
    }
}

@main
private struct BrowserUpdatePolicyTests {
    static func main() throws {
        try testVersionParsingAndComparison()
        try testBuildParsingAndComparison()
        try testPackageNames()
        try testReleaseURLs()
        try testChecksums()
        print("BrowserUpdatePolicyTests: all tests passed")
    }

    private static func testVersionParsingAndComparison() throws {
        try expect(
            BrowserUpdatePolicy.version(in: ["v0.10.2-zh.1"]) == "0.10.2",
            "A formal Chinese release tag did not produce the app version"
        )
        try expect(
            BrowserUpdatePolicy.version(in: ["build-42", "Reynard-0.11.0-abcdef0-unsigned.ipa"]) == "0.11.0",
            "A main-build package name did not produce the app version"
        )
        try expect(BrowserUpdatePolicy.compareVersions("0.10.10", "0.10.2") > 0, "Version comparison is lexical")
        try expect(BrowserUpdatePolicy.compareVersions("1.0", "1.0.0") == 0, "Missing version components are not zero-filled")
    }

    private static func testBuildParsingAndComparison() throws {
        try expect(
            BrowserUpdatePolicy.buildNumber(tagName: "build-52", releaseNotes: "", packageName: "Reynard-0.10.2-a.ipa") == 52,
            "A main-build tag did not produce a build number"
        )
        try expect(
            BrowserUpdatePolicy.buildNumber(
                tagName: "v0.10.2-zh.1",
                releaseNotes: "<!-- reynard-update-build: 53 -->",
                packageName: "Reynard-0.10.2-a.ipa"
            ) == 53,
            "A formal release marker did not produce a build number"
        )
        try expect(
            BrowserUpdatePolicy.isUpdate(
                remoteVersion: "0.10.2",
                remoteBuild: 53,
                currentVersion: "0.10.2",
                currentBuild: 52
            ),
            "A newer build of the same app version was not detected"
        )
        try expect(
            !BrowserUpdatePolicy.isUpdate(
                remoteVersion: "0.10.2",
                remoteBuild: 52,
                currentVersion: "0.10.2",
                currentBuild: 52
            ),
            "The installed build was reported as an update"
        )
    }

    private static func testPackageNames() throws {
        try expect(
            BrowserUpdatePolicy.isAllowedPackageName("Reynard-0.10.2-abcdef0-unsigned.ipa"),
            "A valid unsigned IPA name was rejected"
        )
        try expect(
            BrowserUpdatePolicy.isAllowedPackageName("Reynard-0.10.2-TrollStore.tipa"),
            "A valid TrollStore package name was rejected"
        )
        try expect(!BrowserUpdatePolicy.isAllowedPackageName("../Reynard.ipa"), "A traversal package name was accepted")
        try expect(!BrowserUpdatePolicy.isAllowedPackageName("Other.ipa"), "An unrelated IPA name was accepted")
    }

    private static func testReleaseURLs() throws {
        try expect(
            BrowserUpdatePolicy.isAllowedReleaseDownloadURL(
                URL(string: "https://github.com/xytxg/reynard-browser-zh/releases/download/v0.10.2/Reynard-0.10.2-a.ipa")!
            ),
            "A repository release URL was rejected"
        )
        try expect(
            !BrowserUpdatePolicy.isAllowedReleaseDownloadURL(
                URL(string: "https://example.com/xytxg/reynard-browser-zh/releases/download/v0.10.2/Reynard.ipa")!
            ),
            "A third-party package URL was accepted"
        )
        try expect(
            !BrowserUpdatePolicy.isAllowedReleaseDownloadURL(
                URL(string: "http://github.com/xytxg/reynard-browser-zh/releases/download/v0.10.2/Reynard.ipa")!
            ),
            "An insecure package URL was accepted"
        )
    }

    private static func testChecksums() throws {
        let digest = String(repeating: "ab", count: 32)
        let sidecar = "\(digest)  dist/Reynard-0.10.2-a-unsigned.ipa\n"
        try expect(
            BrowserUpdatePolicy.checksum(
                from: sidecar,
                packageName: "Reynard-0.10.2-a-unsigned.ipa"
            ) == digest,
            "A matching SHA-256 sidecar was not parsed"
        )
        try expect(
            BrowserUpdatePolicy.checksum(from: sidecar, packageName: "Reynard-other.ipa") == nil,
            "A checksum for another package was accepted"
        )
        try expect(
            BrowserUpdatePolicy.checksum(from: "not-a-checksum", packageName: "Reynard.ipa") == nil,
            "Malformed checksum text was accepted"
        )
    }
}
