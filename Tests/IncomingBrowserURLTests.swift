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
private struct IncomingBrowserURLTests {
    static func main() throws {
        try testDirectWebURLs()
        try testWrappedWebURLs()
        try testUnsafeSchemesAreRejected()
        try testInvalidWebURLsAreRejected()
        try testMultipleContextsAreDeterministic()
        try testPermissionOriginIsolation()
        try testTLDTypoCorrection()
        print("IncomingBrowserURLTests: all tests passed")
    }

    private static func testPermissionOriginIsolation() throws {
        let a = URLUtils.permissionOrigin(from: "https://Example.COM/path")
        let b = URLUtils.permissionOrigin(from: "https://example.com:8443/path")
        let c = URLUtils.permissionOrigin(from: "http://example.com")
        try expect(a == "https://example.com", "HTTPS origin normalization failed")
        try expect(b == "https://example.com:8443", "Non-default port must be retained")
        try expect(c == "http://example.com", "HTTP scheme must remain distinct")
        try expect(a != b && a != c && b != c, "Permissions must not cross origins")
        try expect(URLUtils.permissionOrigin(from: "https://example.com:443") == a, "HTTPS default port was not normalized")
        try expect(URLUtils.permissionOrigin(from: "http://example.com:80") == c, "HTTP default port was not normalized")
        try expect(URLUtils.permissionOrigin(from: "example.com") == nil, "Bare host cannot grant permissions")
        try expect(URLUtils.permissionOrigin(from: "file:///private/test") == nil, "File URLs must not grant web permissions")
        try expect(URLUtils.permissionOrigin(from: "https://[::1]:8443/path") == "https://[::1]:8443", "IPv6 origin normalization failed")
    }

    private static func testDirectWebURLs() throws {
        let secureURL = URL(string: "https://example.com/path?q=one#result")!
        let insecureURL = URL(string: "http://localhost:8080/status")!

        try expect(IncomingBrowserURL.resolve(secureURL) == secureURL, "A direct HTTPS URL was changed or rejected")
        try expect(IncomingBrowserURL.resolve(insecureURL) == insecureURL, "A direct HTTP URL was changed or rejected")
    }

    private static func testWrappedWebURLs() throws {
        var components = URLComponents()
        components.scheme = "reynard"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://example.com/a path?q=中文"),
        ]
        let wrappedURL = components.url!
        let resolvedURL = IncomingBrowserURL.resolve(wrappedURL)
        let resolvedComponents = resolvedURL.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }

        try expect(resolvedURL?.scheme == "https", "A wrapped HTTPS URL was rejected")
        try expect(resolvedURL?.host == "example.com", "A wrapped HTTPS URL resolved to the wrong host")
        try expect(
            resolvedComponents?.queryItems?.first(where: { $0.name == "q" })?.value == "中文",
            "A wrapped HTTPS URL lost its query"
        )
    }

    private static func testUnsafeSchemesAreRejected() throws {
        for value in [
            "file:///private/etc/passwd",
            "javascript:alert(1)",
            "data:text/html,test",
            "ftp://example.com/file",
        ] {
            try expect(
                IncomingBrowserURL.resolve(URL(string: value)!) == nil,
                "An unsafe incoming scheme was accepted: \(value)"
            )

            var components = URLComponents()
            components.scheme = "reynard"
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "url", value: value)]
            try expect(
                IncomingBrowserURL.resolve(components.url!) == nil,
                "A wrapped unsafe scheme was accepted: \(value)"
            )
        }
    }

    private static func testInvalidWebURLsAreRejected() throws {
        try expect(
            IncomingBrowserURL.resolve(URL(string: "https:///missing-host")!) == nil,
            "An HTTPS URL without a host was accepted"
        )
        try expect(
            IncomingBrowserURL.resolve(URL(string: "reynard://open")!) == nil,
            "A wrapper without a URL was accepted"
        )
        try expect(
            IncomingBrowserURL.resolve(URL(string: "reynard://open?url=not-a-url")!) == nil,
            "A malformed wrapped URL was accepted"
        )
    }

    private static func testMultipleContextsAreDeterministic() throws {
        let later = URL(string: "https://z.example/path")!
        let earlier = URL(string: "https://a.example/path")!
        let rejected = URL(string: "file:///tmp/ignored")!

        try expect(
            IncomingBrowserURL.firstResolvedURL(in: [later, rejected, earlier]) == earlier,
            "Multiple incoming contexts did not resolve deterministically"
        )
    }
    private static func testTLDTypoCorrection() throws {
        try expect(URLUtils.fixTLDTypo(in: "example.con") == "example.com", "A .con typo was not corrected")
        try expect(
            URLUtils.fixTLDTypo(in: "https://Example.ORG/a?b=c") == "https://Example.ORG/a?b=c",
            "A valid URL was changed"
        )
        try expect(
            URLUtils.fixTLDTypo(in: "http://example.rog:8080/path") == "http://example.org:8080/path",
            "Port and path were not kept when correcting a TLD"
        )
        try expect(URLUtils.fixTLDTypo(in: "ftp://example.con") == "ftp://example.con", "A non-web scheme was rewritten")
        try expect(URLUtils.fixTLDTypo(in: "localhost:3000") == "localhost:3000", "A host without a TLD was rewritten")
        try expect(
            URLUtils.permissionOrigin(from: URLUtils.fixTLDTypo(in: "https://example.cpm")) == "https://example.com",
            "A corrected URL does not map to the corrected permission origin"
        )
    }
}
