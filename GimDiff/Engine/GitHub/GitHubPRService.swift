//
//  GitHubPRService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One snapshot a pull request touches, and where its two versions were downloaded to.
struct PRSnapshotChange: Sendable, Hashable {
    /// What the pull request does to the file, as GitHub reports it.
    enum Kind: String, Sendable {
        case added
        case removed
        case modified
        case renamed

        /// How the change is named to the person reviewing it.
        var title: String {
            switch self {
            case .added: "Added"
            case .removed: "Deleted"
            case .modified: "Modified"
            case .renamed: "Renamed"
            }
        }
    }

    /// Path in the repository at the head of the pull request, or at its base when the
    /// pull request removes the file.
    let path: String
    let kind: Kind
    /// The file as the pull request leaves it; absent when the pull request removes it.
    let candidateURL: URL?
    /// The file as the base branch has it; absent when the pull request adds it.
    let baselineURL: URL?
}

/// A pull request's snapshot changes, downloaded and grouped for review.
///
/// Everything under ``tempDirectoryURL`` belongs to the session and is discarded with it:
/// the files are copies of what GitHub holds, and there is nothing in them to keep.
struct PRReviewSession: Identifiable, Sendable, Equatable {
    /// `owner/repo#123`.
    let id: String
    let reference: GitHubPRReference
    let prNumber: Int
    let title: String
    let author: String
    let baseRef: String
    let headRef: String
    let baseSHA: String
    let headSHA: String
    /// The changed snapshots, grouped the way a scan of the repository would group them.
    let suites: [SnapshotSuite]
    /// Each changed snapshot keyed by its ``SnapshotItem/id``, which is its repository path.
    let changes: [String: PRSnapshotChange]
    /// How many files the pull request changes in all, snapshot or not.
    let changedFileCount: Int
    let tempDirectoryURL: URL
}

/// Fetches a pull request's snapshot changes from GitHub.
protocol GitHubPRService: Sendable {
    func fetchPRSession(reference: GitHubPRReference) async throws -> PRReviewSession
}

/// Why a pull request could not be fetched.
enum GitHubPRServiceError: Error, Equatable {
    /// GitHub turned the token down.
    case unauthorized
    /// The pull request does not exist, or the token cannot see the repository.
    case notFound(GitHubPRReference)
    /// GitHub refused the request, usually over the rate limit.
    case forbidden(message: String)
    /// Any other status GitHub answered with.
    case requestFailed(statusCode: Int, message: String)
    /// GitHub answered with something that is not what its API documents.
    case malformedResponse(String)
}

extension GitHubPRServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "GitHub rejected the token from the GitHub CLI. Run 'gh auth login' in Terminal and try again."
        case let .notFound(reference):
            """
            Pull request \(reference.shortDescription) was not found, or the account the GitHub \
            CLI is logged in with cannot see it.
            """
        case let .forbidden(message):
            "GitHub refused the request: \(message)"
        case let .requestFailed(statusCode, message):
            "GitHub answered with status \(statusCode): \(message)"
        case let .malformedResponse(detail):
            "GitHub sent a response GimDiff could not read: \(detail)"
        }
    }
}

/// Reads a pull request through the GitHub REST API and downloads both versions of every
/// snapshot it changes.
///
/// Nothing is cloned and nothing is checked out: the two versions of each image are fetched
/// by commit, so the review sees exactly the base and head GitHub is showing, whatever the
/// local repository happens to have.
struct DefaultGitHubPRService: GitHubPRService {
    static let apiHost = "api.github.com"
    /// Host that serves the contents of files stored with Git LFS.
    static let mediaHost = "media.githubusercontent.com"
    /// First line of every Git LFS pointer file.
    static let lfsPointerPrefix = Data("version https://git-lfs.github.com/spec/v1".utf8)
    /// Largest page GitHub serves for a pull request's file list.
    static let pageSize = 100
    /// GitHub stops listing a pull request's files at 3,000, which is 30 pages.
    static let maximumPages = 30
    /// Enough to hide latency without inviting GitHub's secondary rate limit.
    static let maximumConcurrentDownloads = 6
    /// Folder names that mark a Swift snapshot. Paparazzi's folder is recognised by its
    /// whole tail instead, through ``PaparazziProvider/isImagesFolder(_:)``.
    static let snapshotFolderNames: Set<String> = [
        SwiftModularProvider.snapshotsFolderName,
        SwiftPointFreeLegacyProvider.snapshotsFolderName,
    ]

    /// Where each side of a change is written, beneath the session's folder.
    static let candidateFolderName = "head"
    static let baselineFolderName = "base"

    private let http: any HTTPClient
    private let tokens: any GitHubTokenProviding
    private let filesystem: any FilesystemService
    private let temporaryRoot: URL

    /// - Parameter temporaryRoot: Folder each session creates its own scratch folder in.
    init(
        http: any HTTPClient,
        tokens: any GitHubTokenProviding,
        filesystem: any FilesystemService,
        temporaryRoot: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("com.davidgiordana.GimDiff.PullRequests", isDirectory: true)
    ) {
        self.http = http
        self.tokens = tokens
        self.filesystem = filesystem
        self.temporaryRoot = temporaryRoot
    }

    func fetchPRSession(reference: GitHubPRReference) async throws -> PRReviewSession {
        let token = try await tokens.token()
        let api = API(http: http, token: token)

        let pull: PullResponse = try await api.decode(
            try api.url(path: "/repos/\(reference.owner)/\(reference.repo)/pulls/\(reference.pullNumber)"),
            reference: reference
        )
        let files = try await changedFiles(of: reference, api: api)
        let snapshotFiles = files.filter { Self.isSnapshotPath($0.filename) }

        let directory = temporaryRoot.appendingPathComponent(
            "\(reference.owner)-\(reference.repo)-\(reference.pullNumber)-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            let changes = try await download(
                snapshotFiles,
                of: pull,
                reference: reference,
                api: api,
                into: directory
            )
            let suites = Self.suites(
                from: changes,
                candidateRoot: directory.appendingPathComponent(Self.candidateFolderName, isDirectory: true)
            )

            return PRReviewSession(
                id: reference.shortDescription,
                reference: reference,
                prNumber: reference.pullNumber,
                title: pull.title,
                author: pull.user.login,
                baseRef: pull.base.ref,
                headRef: pull.head.ref,
                baseSHA: pull.base.sha,
                headSHA: pull.head.sha,
                suites: suites,
                changes: Dictionary(changes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first }),
                changedFileCount: files.count,
                tempDirectoryURL: directory
            )
        } catch {
            // A half-downloaded session is of no use to anyone, and nothing else knows the
            // folder exists to clean it up later.
            if filesystem.fileExists(at: directory) {
                try? filesystem.removeItem(at: directory)
            }
            throw error
        }
    }

    // MARK: - Listing

    private func changedFiles(of reference: GitHubPRReference, api: API) async throws -> [FileResponse] {
        var files: [FileResponse] = []

        for page in 1...Self.maximumPages {
            try Task.checkCancellation()
            let url = try api.url(
                path: "/repos/\(reference.owner)/\(reference.repo)/pulls/\(reference.pullNumber)/files",
                query: [
                    URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            )
            let batch: [FileResponse] = try await api.decode(url, reference: reference)
            files.append(contentsOf: batch)
            // A short page is the last one; asking for the next would only cost a request.
            guard batch.count == Self.pageSize else { break }
        }

        return files
    }

    /// Whether a repository path names an image inside a snapshot folder.
    static func isSnapshotPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let file = components.last,
              ImageFormat(fileExtension: (file as NSString).pathExtension).isRecognized
        else { return false }

        let folders = Array(components.dropLast())
        return folders.contains { snapshotFolderNames.contains($0) }
            || PaparazziProvider.isImagesFolder(folders)
    }

    // MARK: - Downloading

    private func download(
        _ files: [FileResponse],
        of pull: PullResponse,
        reference: GitHubPRReference,
        api: API,
        into directory: URL
    ) async throws -> [PRSnapshotChange] {
        let baseRepository = pull.base.repo?.fullName ?? "\(reference.owner)/\(reference.repo)"
        // A pull request from a fork has its head in the fork. The fork can have been deleted
        // since, in which case GitHub reports no head repository; the base repository still
        // serves the head commit, because the pull request keeps it reachable there.
        let headRepository = pull.head.repo?.fullName ?? baseRepository

        let jobs = files.map { file in
            DownloadJob(
                file: file,
                candidate: file.kind == .removed ? nil : Blob(
                    repository: headRepository,
                    sha: pull.head.sha,
                    path: file.filename,
                    destination: Self.localURL(for: file.filename, in: directory, side: Self.candidateFolderName)
                ),
                baseline: file.kind == .added ? nil : Blob(
                    repository: baseRepository,
                    sha: pull.base.sha,
                    path: file.baselinePath,
                    destination: Self.localURL(for: file.baselinePath, in: directory, side: Self.baselineFolderName)
                )
            )
        }

        return try await withThrowingTaskGroup(of: PRSnapshotChange.self) { group in
            var pending = jobs.makeIterator()
            var changes: [PRSnapshotChange] = []

            func enqueue() {
                guard let job = pending.next() else { return }
                group.addTask { [filesystem] in
                    try await job.run(api: api, filesystem: filesystem, reference: reference)
                }
            }

            for _ in 0..<Self.maximumConcurrentDownloads { enqueue() }
            while let change = try await group.next() {
                changes.append(change)
                enqueue()
            }

            return changes.sorted { $0.path < $1.path }
        }
    }

    /// Mirrors the repository path beneath one side's folder.
    ///
    /// The whole path rather than the file name: two suites recording a test of the same
    /// name write files of the same name, and flattening them would have one overwrite the
    /// other.
    private static func localURL(for path: String, in directory: URL, side: String) -> URL {
        url(forRepositoryPath: path, under: directory.appendingPathComponent(side, isDirectory: true))
    }

    private static func url(forRepositoryPath path: String, under root: URL) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    // MARK: - Grouping

    /// Groups changes into suites the way the providers group a scanned repository.
    ///
    /// `…/Snapshots/<Suite>/…` and `…/__Snapshots__/<Suite>/…` are one suite per folder,
    /// with anything nested deeper prefixed onto the snapshot's name. An image directly
    /// inside the snapshot folder belongs to a suite named after the folder above it, which
    /// is the older swift-snapshot-testing layout. Paparazzi's flat `images` folder is a
    /// suite per test class, read from each file's name as ``PaparazziProvider`` reads it.
    static func suites(from changes: [PRSnapshotChange], candidateRoot: URL) -> [SnapshotSuite] {
        var suitesByID: [String: SnapshotSuite] = [:]

        for change in changes {
            guard let placement = placement(of: change.path) else { continue }

            let item = SnapshotItem(
                id: change.path,
                name: placement.snapshotName,
                variantIndex: placement.variantIndex,
                // A removed snapshot has only its baseline, which is then what there is to see.
                fileURL: change.candidateURL ?? change.baselineURL ?? candidateRoot,
                gitStatus: .modified
            )

            if suitesByID[placement.suiteID] == nil {
                suitesByID[placement.suiteID] = SnapshotSuite(
                    id: placement.suiteID,
                    name: placement.suiteName,
                    snapshotsFolderURL: url(forRepositoryPath: placement.suiteFolder, under: candidateRoot),
                    providerId: placement.providerId,
                    sharesFolder: placement.sharesFolder
                )
            }
            suitesByID[placement.suiteID]?.snapshots.append(item)
        }

        return suitesByID.values
            .map { suite in
                var sorted = suite
                sorted.snapshots.sort { $0.id < $1.id }
                return sorted
            }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    private struct Placement {
        var suiteID: String
        var suiteName: String
        var suiteFolder: String
        var providerId: String
        var sharesFolder = false
        var snapshotName: String
        var variantIndex: Int?
    }

    /// Where a snapshot path sits: its suite, and the name it is listed under.
    private static func placement(of path: String) -> Placement? {
        let components = path.split(separator: "/").map(String.init)
        let folders = components.dropLast()

        if PaparazziProvider.isImagesFolder(Array(folders)) {
            return paparazziPlacement(of: path, in: Array(folders))
        }

        guard let placement = swiftPlacement(in: folders) else { return nil }
        let decomposed = SnapshotItem.decomposeName(of: URL(fileURLWithPath: path))
        return Placement(
            suiteID: placement.suiteFolder,
            suiteName: placement.suiteName,
            suiteFolder: placement.suiteFolder,
            providerId: placement.providerId,
            snapshotName: placement.nestedFolders.isEmpty
                ? decomposed.name
                : placement.nestedFolders.joined(separator: "/") + "/" + decomposed.name,
            variantIndex: decomposed.variantIndex
        )
    }

    /// A Paparazzi image's class, read from its name alone: the review has no sources to
    /// settle where an underscored package ends, so the first two separators decide.
    private static func paparazziPlacement(of path: String, in folders: [String]) -> Placement {
        let folder = folders.joined(separator: "/")
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let module = folders.dropLast(4).last ?? folder
        let recorded = PaparazziProvider.recordedName(of: stem)
            ?? PaparazziProvider.RecordedName(packageName: "", className: module, snapshotName: stem)

        return Placement(
            suiteID: folder + "/" + recorded.packageName + PaparazziProvider.delimiter + recorded.className,
            suiteName: recorded.className,
            suiteFolder: folder,
            providerId: PaparazziProvider().id,
            sharesFolder: true,
            snapshotName: recorded.snapshotName
        )
    }

    private struct SwiftPlacement {
        var suiteName: String
        var suiteFolder: String
        var nestedFolders: [String]
        var providerId: String
    }

    /// The suite a Swift snapshot folder holds, and the folders between it and the file.
    ///
    /// The snapshot folder nearest the file wins, so a repository that happens to keep a
    /// `Snapshots` folder further up its tree still groups by the one that holds the image.
    private static func swiftPlacement(in folders: ArraySlice<String>) -> SwiftPlacement? {
        guard let markerIndex = folders.lastIndex(where: { snapshotFolderNames.contains($0) }) else {
            return nil
        }

        let marker = folders[markerIndex]
        let providerId = marker == SwiftPointFreeLegacyProvider.snapshotsFolderName
            ? "swift.pointfree"
            : "swift.modular"

        if markerIndex == folders.index(before: folders.endIndex) {
            let parent = markerIndex > folders.startIndex ? folders[markerIndex - 1] : marker
            return SwiftPlacement(
                suiteName: parent,
                suiteFolder: folders[...markerIndex].joined(separator: "/"),
                nestedFolders: [],
                providerId: providerId
            )
        }

        let suiteIndex = markerIndex + 1
        return SwiftPlacement(
            suiteName: folders[suiteIndex],
            suiteFolder: folders[...suiteIndex].joined(separator: "/"),
            nestedFolders: Array(folders[(suiteIndex + 1)...]),
            providerId: providerId
        )
    }
}

// MARK: - API

private extension DefaultGitHubPRService {
    /// The authenticated half of the service: builds requests and interprets statuses.
    struct API: Sendable {
        let http: any HTTPClient
        let token: String

        func url(
            path: String,
            query: [URLQueryItem] = [],
            host: String = DefaultGitHubPRService.apiHost
        ) throws -> URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.percentEncodedPath = path
            if !query.isEmpty {
                components.queryItems = query
            }
            guard let url = components.url else {
                throw GitHubPRServiceError.malformedResponse("could not build a request for \(path)")
            }
            return url
        }

        /// The raw bytes of one file at one commit, through the contents API.
        ///
        /// The contents API rather than `raw.githubusercontent.com`: it answers to the same
        /// token as every other request here, private repositories included, and reports a
        /// missing file as a status rather than as an HTML page.
        ///
        /// Snapshot folders are often stored with Git LFS, and for those the contents API
        /// answers with the pointer file rather than the image. A pointer is recognised by
        /// its first line and the image is fetched from GitHub's media host instead.
        func blob(_ blob: Blob, reference: GitHubPRReference) async throws -> Data {
            let path = Self.encodedPath(blob.path)
            let url = try url(
                path: "/repos/\(blob.repository)/contents/\(path)",
                query: [URLQueryItem(name: "ref", value: blob.sha)]
            )
            let data = try await get(url, accept: "application/vnd.github.raw+json", reference: reference)
            guard data.starts(with: DefaultGitHubPRService.lfsPointerPrefix) else { return data }

            let media = try self.url(
                path: "/media/\(blob.repository)/\(blob.sha)/\(path)",
                host: DefaultGitHubPRService.mediaHost
            )
            return try await get(media, accept: "application/octet-stream", reference: reference)
        }

        func decode<Value: Decodable>(_ url: URL, reference: GitHubPRReference) async throws -> Value {
            let data = try await get(url, accept: "application/vnd.github+json", reference: reference)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                return try decoder.decode(Value.self, from: data)
            } catch {
                throw GitHubPRServiceError.malformedResponse(url.path)
            }
        }

        private func get(_ url: URL, accept: String, reference: GitHubPRReference) async throws -> Data {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(accept, forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("GimDiff", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await http.data(for: request)
            try Task.checkCancellation()

            switch response.statusCode {
            case 200..<300:
                return data
            case 401:
                throw GitHubPRServiceError.unauthorized
            case 404:
                throw GitHubPRServiceError.notFound(reference)
            case 403, 429:
                throw GitHubPRServiceError.forbidden(message: Self.message(in: data, status: response.statusCode))
            default:
                throw GitHubPRServiceError.requestFailed(
                    statusCode: response.statusCode,
                    message: Self.message(in: data, status: response.statusCode)
                )
            }
        }

        /// GitHub's own explanation of a failure, which is more useful than the status alone.
        private static func message(in data: Data, status: Int) -> String {
            struct ErrorBody: Decodable { let message: String }
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                return body.message
            }
            return HTTPURLResponse.localizedString(forStatusCode: status)
        }

        /// Percent-encodes each segment of a repository path, keeping the separators.
        private static func encodedPath(_ path: String) -> String {
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/;")
            return path
                .split(separator: "/", omittingEmptySubsequences: false)
                .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
                .joined(separator: "/")
        }
    }

    /// One version of one file: a path at a commit in a repository.
    struct Blob: Sendable {
        /// `owner/repo`.
        let repository: String
        let sha: String
        let path: String
        let destination: URL
    }

    struct DownloadJob: Sendable {
        let file: FileResponse
        let candidate: Blob?
        let baseline: Blob?

        func run(
            api: API,
            filesystem: any FilesystemService,
            reference: GitHubPRReference
        ) async throws -> PRSnapshotChange {
            for blob in [candidate, baseline].compactMap({ $0 }) {
                let data = try await api.blob(blob, reference: reference)
                try filesystem.writeFile(at: blob.destination, data: data)
            }

            return PRSnapshotChange(
                path: file.filename,
                kind: file.kind,
                candidateURL: candidate?.destination,
                baselineURL: baseline?.destination
            )
        }
    }

    // MARK: Responses

    struct PullResponse: Decodable, Sendable {
        struct User: Decodable, Sendable {
            let login: String
        }

        struct Branch: Decodable, Sendable {
            let ref: String
            let sha: String
            /// Absent when the repository the branch lived in has been deleted.
            let repo: Repository?
        }

        struct Repository: Decodable, Sendable {
            let fullName: String
        }

        let title: String
        let user: User
        let base: Branch
        let head: Branch
    }

    struct FileResponse: Decodable, Sendable {
        let filename: String
        let status: String
        let previousFilename: String?

        var kind: PRSnapshotChange.Kind {
            switch status {
            case "added": .added
            case "removed": .removed
            case "renamed", "copied": .renamed
            default: .modified
            }
        }

        /// Where the base branch keeps the file, which a rename moved.
        var baselinePath: String {
            kind == .renamed ? previousFilename ?? filename : filename
        }
    }
}
