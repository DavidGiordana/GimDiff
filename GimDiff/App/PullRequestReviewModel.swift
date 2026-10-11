//
//  PullRequestReviewModel.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A GitHub pull request under review: the Open PR sheet, the fetch behind it, and the
/// downloaded snapshots once it lands.
///
/// Owns the review and nothing about the window. Putting a fetched review in the tree, and
/// putting the project back when it closes, is ``AppState``'s: a fetch hands its session
/// back rather than showing it; see ``fetch(_:repositoryRoot:deliver:)``.
@MainActor
@Observable
final class PullRequestReviewModel {
    /// The pull request the sidebar is showing in place of a project, if any.
    private(set) var session: PRReviewSession?
    /// Whether the Open PR sheet is up.
    ///
    /// Every route into a review — the menu, a paste, a `gimdiff://open-pr` URL — goes
    /// through the sheet, so a fetch that takes a while has one place to show progress and
    /// a failure has one place to be read.
    private(set) var isSheetPresented = false
    /// What the sheet's field holds: a link, `owner/repo#123`, or a number.
    var input = ""
    private(set) var isFetching = false
    /// Why the last fetch failed, shown in the sheet rather than on the window's banner.
    private(set) var error: String?
    /// The project the review replaced, put back when the review closes.
    private(set) var projectBeforeReview: ProjectBundle?

    /// Where a scratch folder that would not delete is reported, which is the window's
    /// banner. Set by ``AppState`` once it exists.
    @ObservationIgnored var reportError: @MainActor (any Error) -> Void = { _ in }

    @ObservationIgnored private let service: any GitHubPRService
    @ObservationIgnored private let resolver: GitHubPRReferenceResolver
    @ObservationIgnored private let filesystem: any FilesystemService
    @ObservationIgnored private var fetchTask: Task<Void, Never>?

    init(
        service: any GitHubPRService,
        resolver: GitHubPRReferenceResolver,
        filesystem: any FilesystemService
    ) {
        self.service = service
        self.resolver = resolver
        self.filesystem = filesystem
    }

    /// Whether the sidebar is showing a pull request rather than a project on disk.
    var isReviewing: Bool { session != nil }

    /// What the pull request under review does to a snapshot, or `nil` outside a review.
    func change(forSnapshotID id: String?) -> PRSnapshotChange? {
        guard let id else { return nil }
        return session?.changes[id]
    }

    // MARK: - Sheet

    /// Raises the sheet, filled in with `prefill` when the field is empty and no fetch is
    /// showing its progress there.
    ///
    /// - Parameter prefill: Read only when it would be used, since it reads the clipboard.
    func presentSheet(prefill: () -> String?) {
        if !isFetching {
            error = nil
            if input.isEmpty, let prefilled = prefill() {
                input = prefilled
            }
        }
        isSheetPresented = true
    }

    /// Puts the sheet away, abandoning a fetch still in flight.
    func dismissSheet() {
        fetchTask?.cancel()
        fetchTask = nil
        isFetching = false
        error = nil
        isSheetPresented = false
    }

    // MARK: - Fetching

    /// Fetches the pull request `input` names, showing progress in the sheet.
    ///
    /// - Parameters:
    ///   - repositoryRoot: The open project's repository, which a bare number refers to.
    ///   - deliver: Shows the session once its snapshots are downloaded. Called only for a
    ///     fetch nothing has superseded; the caller then calls ``begin(_:replacing:)``.
    func fetch(
        _ input: String,
        repositoryRoot: URL?,
        deliver: @escaping @MainActor (PRReviewSession) -> Void
    ) {
        self.input = input
        error = nil
        isSheetPresented = true

        fetchTask?.cancel()
        isFetching = true

        let preferred = session?.reference.repository
        fetchTask = Task { [service, resolver] in
            do {
                let reference = try await resolver.reference(
                    for: input,
                    repositoryRoot: repositoryRoot,
                    preferredRepository: preferred
                )
                let session = try await service.fetchPRSession(reference: reference)
                guard !Task.isCancelled else {
                    discardFiles(of: session)
                    return
                }
                deliver(session)
            } catch {
                // A cancelled download reports itself as a `URLError`, not as a
                // `CancellationError`, so the task is asked rather than the error.
                guard !Task.isCancelled else { return }
                isFetching = false
                self.error = error.localizedDescription
            }
        }
    }

    /// The fetch in flight, if any, so a caller can wait for it.
    var currentFetch: Task<Void, Never>? { fetchTask }

    // MARK: - Review

    /// Makes `session` the review, and puts the sheet away.
    ///
    /// A second review replaces the first, but the project behind both stays the one to go
    /// back to: `project` is only remembered when no review was already up.
    func begin(_ session: PRReviewSession, replacing project: ProjectBundle?) {
        if let current = self.session {
            discardFiles(of: current)
        } else {
            projectBeforeReview = project
        }
        self.session = session
    }

    /// Clears the sheet once the review it fetched is on screen.
    func finishFetch() {
        isFetching = false
        isSheetPresented = false
        input = ""
    }

    /// Ends the review without restoring anything, deleting what it downloaded.
    func abandon() {
        fetchTask?.cancel()
        fetchTask = nil
        isFetching = false
        guard let session else { return }
        discardFiles(of: session)
        self.session = nil
        projectBeforeReview = nil
    }

    /// Deletes the downloaded snapshots of the review in progress, for the app to call on
    /// its way out.
    func discardFiles() {
        fetchTask?.cancel()
        guard let session else { return }
        discardFiles(of: session)
    }

    /// Deleted rather than trashed: the copies are GimDiff's own, and a review a day would
    /// otherwise fill the Trash with folders nobody asked to keep.
    private func discardFiles(of session: PRReviewSession) {
        guard filesystem.fileExists(at: session.tempDirectoryURL) else { return }
        do {
            try filesystem.removeItem(at: session.tempDirectoryURL)
        } catch {
            reportError(error)
        }
    }
}
