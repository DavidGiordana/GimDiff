//
//  GitHubPRServiceTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("GitHub pull request snapshot service")
struct GitHubPRServiceTests {
    private static let reference = GitHubPRReference(owner: "octo", repo: "app", pullNumber: 7)
    private static let temporaryRoot = URL(fileURLWithPath: "/mock-tmp/PullRequests", isDirectory: true)
    private static let baseSHA = "base000"
    private static let headSHA = "head111"

    // MARK: - Building a session

    @Test("Reads the pull request's title, author, and both branches")
    func readsMetadata() async throws {
        let fixture = Fixture(files: [])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(session.id == "octo/app#7")
        #expect(session.prNumber == 7)
        #expect(session.title == "Refresh the home screen")
        #expect(session.author == "mona")
        #expect(session.baseRef == "main")
        #expect(session.headRef == "feature/home")
        #expect(session.baseSHA == Self.baseSHA)
        #expect(session.headSHA == Self.headSHA)
        #expect(session.tempDirectoryURL.path.hasPrefix(Self.temporaryRoot.path + "/octo-app-7-"))
    }

    @Test("Groups changed snapshots into suites the way the providers group a scan")
    func groupsSuites() async throws {
        let fixture = Fixture(files: [
            .modified("Features/Home/Tests/Snapshots/HomeTests/testHome.1.png"),
            .modified("Features/Home/Tests/Snapshots/HomeTests/iPhone/testHome.1.png"),
            .modified("Tests/__Snapshots__/ButtonTests/testPrimary.png"),
            .modified("Legacy/LegacyTests/__Snapshots__/testOld.2.png"),
        ])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(session.suites.map(\.name) == ["ButtonTests", "HomeTests", "LegacyTests"])

        let home = try #require(session.suites.first { $0.name == "HomeTests" })
        #expect(home.id == "Features/Home/Tests/Snapshots/HomeTests")
        #expect(home.providerId == "swift.modular")
        #expect(home.snapshots.map(\.displayName) == ["iPhone/testHome (1)", "testHome (1)"])

        let button = try #require(session.suites.first { $0.name == "ButtonTests" })
        #expect(button.providerId == "swift.pointfree")
        #expect(button.snapshots.map(\.displayName) == ["testPrimary"])

        let legacy = try #require(session.suites.first { $0.name == "LegacyTests" })
        #expect(legacy.snapshots.map(\.displayName) == ["testOld (2)"])

        let everySnapshot = session.suites.flatMap(\.snapshots)
        #expect(everySnapshot.allSatisfy { $0.gitStatus == .modified })
    }

    @Test("Groups Paparazzi images by test class, each suite sharing its module's folder")
    func groupsPaparazziSuites() async throws {
        let fixture = Fixture(files: [
            .modified("app/src/test/snapshots/images/com.example_LaunchViewTest_pixel5.png"),
            .modified("app/src/test/snapshots/images/com.example_LaunchViewTest_pixel5_dark.png"),
            .modified("app/src/test/snapshots/images/com.example_ButtonTest_primary.png"),
            .modified("app/src/test/snapshots/videos/com.example_LaunchViewTest_intro.mov"),
            .modified("docs/images/com.example_LaunchViewTest_pixel5.png"),
        ])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(session.suites.map(\.name) == ["ButtonTest", "LaunchViewTest"])
        #expect(session.suites.allSatisfy { $0.providerId == "android.paparazzi" && $0.sharesFolder })

        let launch = try #require(session.suites.first { $0.name == "LaunchViewTest" })
        #expect(launch.id == "app/src/test/snapshots/images/com.example_LaunchViewTest")
        #expect(launch.snapshots.map(\.displayName) == ["pixel5", "pixel5_dark"])
    }

    @Test("Ignores files that are not images inside a snapshot folder")
    func filtersNonSnapshots() async throws {
        let fixture = Fixture(files: [
            .modified("Sources/App/HomeView.swift"),
            .modified("docs/screenshot.png"),
            .modified("Tests/Snapshots/HomeTests/notes.txt"),
            .modified("Tests/Snapshots/HomeTests/testHome.webp"),
            .modified("Tests/Snapshots/HomeTests/testHome.jpeg"),
        ])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(session.changedFileCount == 5)
        #expect(session.suites.flatMap(\.snapshots).map(\.id) == [
            "Tests/Snapshots/HomeTests/testHome.jpeg",
            "Tests/Snapshots/HomeTests/testHome.webp",
        ])
        let contentRequests = fixture.http.requestedPaths.filter { $0.contains("/contents/") }
        #expect(contentRequests.count == 4)
    }

    @Test("A pull request touching no snapshot yields a session with no suites")
    func noSnapshotChanges() async throws {
        let fixture = Fixture(files: [.modified("README.md"), .modified("Sources/App.swift")])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(session.suites.isEmpty)
        #expect(session.changes.isEmpty)
        #expect(session.changedFileCount == 2)
    }

    // MARK: - Downloading

    @Test("Downloads both versions of a modified snapshot into the session's folder")
    func downloadsBothSides() async throws {
        let path = "Tests/Snapshots/HomeTests/testHome.png"
        let fixture = Fixture(files: [.modified(path)])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        let change = try #require(session.changes[path])
        let candidate = try #require(change.candidateURL)
        let baseline = try #require(change.baselineURL)
        #expect(candidate == session.tempDirectoryURL.appendingPathComponent("head/\(path)"))
        #expect(baseline == session.tempDirectoryURL.appendingPathComponent("base/\(path)"))
        #expect(fixture.filesystem.contents(of: candidate) == "head:\(path)")
        #expect(fixture.filesystem.contents(of: baseline) == "base:\(path)")

        let snapshot = try #require(session.suites.first?.snapshots.first)
        #expect(snapshot.id == path)
        #expect(snapshot.fileURL == candidate)
    }

    @Test("Snapshots of the same name in different suites do not overwrite each other")
    func keepsSameNamedFilesApart() async throws {
        let first = "A/Snapshots/HomeTests/testHome.png"
        let second = "B/Snapshots/HomeTests/testHome.png"
        let fixture = Fixture(files: [.modified(first), .modified(second)])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        let firstURL = try #require(session.changes[first]?.candidateURL)
        let secondURL = try #require(session.changes[second]?.candidateURL)
        #expect(firstURL != secondURL)
        #expect(fixture.filesystem.contents(of: firstURL) == "head:\(first)")
        #expect(fixture.filesystem.contents(of: secondURL) == "head:\(second)")
        #expect(session.suites.count == 2)
    }

    @Test("An added snapshot has no baseline, and a removed one no candidate")
    func addedAndRemoved() async throws {
        let added = "Tests/Snapshots/HomeTests/testNew.png"
        let removed = "Tests/Snapshots/HomeTests/testGone.png"
        let fixture = Fixture(files: [
            FileEntry(filename: added, status: "added"),
            FileEntry(filename: removed, status: "removed"),
        ])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        let addedChange = try #require(session.changes[added])
        #expect(addedChange.kind == .added)
        #expect(addedChange.candidateURL != nil)
        #expect(addedChange.baselineURL == nil)

        let removedChange = try #require(session.changes[removed])
        #expect(removedChange.kind == .removed)
        #expect(removedChange.candidateURL == nil)
        let removedSnapshot = try #require(session.suites.first?.snapshots.first { $0.id == removed })
        #expect(removedSnapshot.fileURL == removedChange.baselineURL)

        #expect(!fixture.http.requestedPaths.contains { $0.contains("testNew.png?ref=\(Self.baseSHA)") })
        #expect(!fixture.http.requestedPaths.contains { $0.contains("testGone.png?ref=\(Self.headSHA)") })
    }

    @Test("A renamed snapshot's baseline is read from where the base branch keeps it")
    func renamedReadsPreviousPath() async throws {
        let old = "Tests/Snapshots/HomeTests/testHome.png"
        let new = "Tests/Snapshots/HomeTests/testHomeScreen.png"
        let fixture = Fixture(files: [FileEntry(filename: new, status: "renamed", previousFilename: old)])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        let change = try #require(session.changes[new])
        let baseline = try #require(change.baselineURL)
        #expect(change.kind == .renamed)
        #expect(fixture.filesystem.contents(of: baseline) == "base:\(old)")
    }

    @Test("A pull request from a fork reads its head from the fork")
    func forkHeadComesFromFork() async throws {
        let path = "Tests/Snapshots/HomeTests/testHome.png"
        let fixture = Fixture(files: [.modified(path)], headRepository: "mona/app")

        _ = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(fixture.http.requestedPaths.contains("/repos/mona/app/contents/\(path)?ref=\(Self.headSHA)"))
        #expect(fixture.http.requestedPaths.contains("/repos/octo/app/contents/\(path)?ref=\(Self.baseSHA)"))
    }

    @Test("A snapshot stored with Git LFS is fetched from the media host, not left as a pointer")
    func resolvesLFSPointers() async throws {
        let path = "Tests/Snapshots/HomeTests/testHome.png"
        let fixture = Fixture(files: [.modified(path)])
        let pointer = """
            version https://git-lfs.github.com/spec/v1
            oid sha256:66ea31e28b8dfff49c74946267110540e92e7abb7fa9bd09c58e829d61514c58
            size 122092

            """
        fixture.http.stub("/repos/octo/app/contents/\(path)?ref=\(Self.headSHA)", body: pointer)
        fixture.http.stub("/media/octo/app/\(Self.headSHA)/\(path)", body: "lfs-image")

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        let candidate = try #require(session.changes[path]?.candidateURL)
        #expect(fixture.filesystem.contents(of: candidate) == "lfs-image")
        let media = try #require(fixture.http.requests.first { $0.url?.path.hasPrefix("/media/") == true })
        #expect(media.url?.host == "media.githubusercontent.com")
        #expect(media.value(forHTTPHeaderField: "Authorization") == "Bearer gho_test")
    }

    @Test("Paths are percent-encoded one segment at a time")
    func encodesPaths() async throws {
        let path = "Tests/Snapshots/Home Tests/test#1.png"
        let fixture = Fixture(files: [.modified(path)])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(fixture.http.requestedPaths.contains(
            "/repos/octo/app/contents/Tests/Snapshots/Home%20Tests/test%231.png?ref=\(Self.headSHA)"
        ))
        #expect(session.suites.map(\.name) == ["Home Tests"])
    }

    @Test("Every request carries the token and GitHub's media type")
    func sendsCredentials() async throws {
        let fixture = Fixture(files: [.modified("Tests/Snapshots/HomeTests/testHome.png")])

        _ = try await fixture.service.fetchPRSession(reference: Self.reference)

        let requests = fixture.http.requests
        #expect(!requests.isEmpty)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer gho_test" })
        #expect(requests.allSatisfy { $0.url?.host == "api.github.com" })

        let pull = try #require(requests.first { $0.url?.path == "/repos/octo/app/pulls/7" })
        #expect(pull.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        let blob = try #require(requests.first { $0.url?.path.contains("/contents/") == true })
        #expect(blob.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
    }

    @Test("A full page of files is followed by the next one")
    func paginatesFileList() async throws {
        let firstPage = (0..<100).map { FileEntry.modified("Sources/File\($0).swift") }
        let fixture = Fixture(
            files: firstPage,
            secondPage: [.modified("Tests/Snapshots/HomeTests/testHome.png")]
        )

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(session.changedFileCount == 101)
        #expect(session.suites.flatMap(\.snapshots).map(\.id) == ["Tests/Snapshots/HomeTests/testHome.png"])
        #expect(fixture.http.requestedPaths.contains("/repos/octo/app/pulls/7/files?per_page=100&page=2"))
        #expect(!fixture.http.requestedPaths.contains("/repos/octo/app/pulls/7/files?per_page=100&page=3"))
    }

    @Test("The count GitHub reports is kept beside the files it listed")
    func keepsTheReportedCount() async throws {
        let fixture = Fixture(files: [.modified("Tests/Snapshots/HomeTests/testHome.png")], changedFiles: 4_812)

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(session.changedFileCount == 1)
        #expect(session.reportedChangedFileCount == 4_812)
        #expect(session.unlistedFileCount == 4_811)
    }

    @Test("A response without a count leaves nothing unlisted")
    func missingCountMeansComplete() async throws {
        let fixture = Fixture(files: [.modified("Tests/Snapshots/HomeTests/testHome.png")])

        let session = try await fixture.service.fetchPRSession(reference: Self.reference)

        #expect(session.reportedChangedFileCount == nil)
        #expect(session.unlistedFileCount == 0)
    }

    // MARK: - Failures

    @Test("A pull request GitHub does not know is reported as not found")
    func reportsNotFound() async {
        let fixture = Fixture(files: [])
        fixture.http.stub("/repos/octo/app/pulls/7", status: 404, body: #"{"message":"Not Found"}"#)

        await #expect(throws: GitHubPRServiceError.notFound(Self.reference)) {
            try await fixture.service.fetchPRSession(reference: Self.reference)
        }
    }

    @Test("A rejected token is reported as such")
    func reportsUnauthorized() async {
        let fixture = Fixture(files: [])
        fixture.http.stub("/repos/octo/app/pulls/7", status: 401, body: #"{"message":"Bad credentials"}"#)

        await #expect(throws: GitHubPRServiceError.unauthorized) {
            try await fixture.service.fetchPRSession(reference: Self.reference)
        }
    }

    @Test("GitHub's own explanation is passed on for a refusal")
    func reportsRateLimit() async {
        let fixture = Fixture(files: [])
        fixture.http.stub("/repos/octo/app/pulls/7", status: 403, body: #"{"message":"API rate limit exceeded"}"#)

        await #expect(throws: GitHubPRServiceError.forbidden(message: "API rate limit exceeded")) {
            try await fixture.service.fetchPRSession(reference: Self.reference)
        }
    }

    @Test("A failed download removes whatever the session had already written")
    func cleansUpAfterFailedDownload() async throws {
        let good = "Tests/Snapshots/HomeTests/a.png"
        let bad = "Tests/Snapshots/HomeTests/b.png"
        let fixture = Fixture(files: [.modified(good), .modified(bad)])
        fixture.http.stub("/repos/octo/app/contents/\(bad)?ref=\(Self.baseSHA)", status: 500, body: "{}")

        await #expect(throws: GitHubPRServiceError.self) {
            try await fixture.service.fetchPRSession(reference: Self.reference)
        }

        #expect(!fixture.filesystem.files.keys.contains { $0.hasPrefix(Self.temporaryRoot.path) })
        #expect(fixture.filesystem.removedPaths.count == 1)
    }

    @Test("A missing token stops the fetch before anything is requested")
    func tokenFailureStopsEarly() async {
        let fixture = Fixture(files: [], token: .failure(GitHubCLIAuthError.notAuthenticated))

        await #expect(throws: GitHubCLIAuthError.notAuthenticated) {
            try await fixture.service.fetchPRSession(reference: Self.reference)
        }
        #expect(fixture.http.requests.isEmpty)
    }
}

// MARK: - Fixture

/// One entry of a pull request's file list, as GitHub reports it.
private struct FileEntry {
    var filename: String
    var status: String
    var previousFilename: String?

    static func modified(_ filename: String) -> FileEntry {
        FileEntry(filename: filename, status: "modified")
    }

    var json: [String: Any] {
        var object: [String: Any] = ["filename": filename, "status": status]
        if let previousFilename { object["previous_filename"] = previousFilename }
        return object
    }
}

/// A service wired to a canned GitHub, with every blob answering with its own path.
private struct Fixture {
    let http = StubHTTPClient()
    let filesystem = MockFilesystemService()
    let service: DefaultGitHubPRService

    init(
        files: [FileEntry],
        secondPage: [FileEntry]? = nil,
        headRepository: String = "octo/app",
        changedFiles: Int? = nil,
        token: Result<String, any Error> = .success("gho_test")
    ) {
        service = DefaultGitHubPRService(
            http: http,
            tokens: StubTokenProvider(result: token),
            filesystem: filesystem,
            temporaryRoot: URL(fileURLWithPath: "/mock-tmp/PullRequests", isDirectory: true)
        )

        var pull: [String: Any] = [
            "title": "Refresh the home screen",
            "user": ["login": "mona"],
            "base": ["ref": "main", "sha": "base000", "repo": ["full_name": "octo/app"]],
            "head": ["ref": "feature/home", "sha": "head111", "repo": ["full_name": headRepository]],
        ]
        if let changedFiles { pull["changed_files"] = changedFiles }
        http.stub("/repos/octo/app/pulls/7", json: pull)
        http.stub("/repos/octo/app/pulls/7/files?per_page=100&page=1", json: files.map(\.json))
        if let secondPage {
            http.stub("/repos/octo/app/pulls/7/files?per_page=100&page=2", json: secondPage.map(\.json))
        }
        // Anything under /contents/ that was not stubbed answers with its own path, so an
        // assertion can tell which side of which file landed where.
        http.fallback = { path in
            guard let range = path.range(of: "/contents/") else { return nil }
            let remainder = path[range.upperBound...]
            guard let query = remainder.range(of: "?ref=") else { return nil }
            let file = String(remainder[..<query.lowerBound]).removingPercentEncoding ?? ""
            let side = remainder[query.upperBound...] == "head111" ? "head" : "base"
            return Data("\(side):\(file)".utf8)
        }
    }
}

/// An ``HTTPClient`` that answers from a table keyed by path and query.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: (status: Int, body: Data)] = [:]
    private var recorded: [URLRequest] = []
    /// Consulted for any path the table does not hold; `nil` from it is a 404.
    var fallback: (@Sendable (String) -> Data?)?

    var requests: [URLRequest] { lock.withLock { recorded } }

    /// Each request's percent-encoded path and query, in the order they were made.
    var requestedPaths: [String] { requests.compactMap { $0.url.map(Self.key(for:)) } }

    func stub(_ path: String, status: Int = 200, body: String) {
        lock.withLock { responses[path] = (status, Data(body.utf8)) }
    }

    func stub(_ path: String, json: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        lock.withLock { responses[path] = (200, data) }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let key = Self.key(for: url)
        let (response, fallback) = lock.withLock {
            recorded.append(request)
            return (responses[key], self.fallback)
        }

        let status: Int
        let body: Data
        if let response {
            (status, body) = response
        } else if let data = fallback?(key) {
            (status, body) = (200, data)
        } else {
            (status, body) = (404, Data(#"{"message":"Not Found"}"#.utf8))
        }

        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return (body, http)
    }

    private static func key(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? url.path
        guard let query = components?.percentEncodedQuery else { return path }
        return path + "?" + query
    }
}

struct StubTokenProvider: GitHubTokenProviding {
    var result: Result<String, any Error> = .success("gho_test")

    func token() async throws -> String {
        try result.get()
    }
}
