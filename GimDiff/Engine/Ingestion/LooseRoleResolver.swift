//
//  LooseRoleResolver.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// What the files themselves said about which of two loose images is the baseline.
enum LooseRoleEvidence: Equatable, Sendable {
    /// Git tracks the baseline and not the other image.
    case trackedByGit
    /// The baseline is inside the open project and the other image is outside it.
    case insideProject
}

/// How sure GimDiff is about which of two loose images is the baseline.
enum LooseRoleCertainty: Equatable, Sendable {
    /// Whoever handed the pair over said which was which: a URL, the command line, or a log
    /// that labelled both paths, and nothing about the files disagreed.
    case stated
    /// The files decided. `swapped` when that reversed what the source said or the order
    /// it listed the images in.
    case inferred(LooseRoleEvidence, swapped: Bool)
    /// Nothing told the two apart. The sides are in the order the source gave them, and
    /// nothing on screen should claim either one is the baseline.
    case unknown
}

/// Two loose images, assigned to their sides.
struct LooseRoleResolution: Equatable, Sendable {
    var baselineURL: URL
    var candidateURL: URL
    var certainty: LooseRoleCertainty
}

/// Decides which of two images handed over from outside — pasted, dropped — is the baseline.
///
/// Evidence comes from the files rather than from their names, so no snapshot library's
/// folder layout is assumed. A recorded snapshot is committed; what a failing run wrote is
/// not. A recorded snapshot lives in the project; a failure artifact usually lands in a
/// temporary folder outside it. Either asymmetry is enough, and it outranks what a log said,
/// since a log's labels are read out of prose and can be misread. When neither file stands
/// apart, the source's word is kept if it gave one, and the pair is reported as undecided
/// if it did not.
struct LooseRoleResolver: Sendable {
    let gitService: any GitService

    /// - Parameters:
    ///   - baseline: The image the source put on the baseline side.
    ///   - candidate: The image the source put on the candidate side.
    ///   - rolesAreStated: Whether the source labelled the sides or only listed them.
    ///   - projectRoot: The open project, whose files count as recorded ones.
    func resolve(
        baseline: URL,
        candidate: URL,
        rolesAreStated: Bool,
        projectRoot: URL?
    ) async -> LooseRoleResolution {
        guard let (firstIsBaseline, evidence) = await verdict(baseline, candidate, projectRoot: projectRoot) else {
            return LooseRoleResolution(
                baselineURL: baseline,
                candidateURL: candidate,
                certainty: rolesAreStated ? .stated : .unknown
            )
        }

        if firstIsBaseline {
            // Agreeing with labels the source gave adds nothing worth saying.
            return LooseRoleResolution(
                baselineURL: baseline,
                candidateURL: candidate,
                certainty: rolesAreStated ? .stated : .inferred(evidence, swapped: false)
            )
        }
        return LooseRoleResolution(
            baselineURL: candidate,
            candidateURL: baseline,
            certainty: .inferred(evidence, swapped: true)
        )
    }

    /// Whether `first` is the baseline, and what said so; `nil` when nothing did.
    private func verdict(
        _ first: URL,
        _ second: URL,
        projectRoot: URL?
    ) async -> (firstIsBaseline: Bool, evidence: LooseRoleEvidence)? {
        if let firstTracked = await isTracked(first),
           let secondTracked = await isTracked(second),
           firstTracked != secondTracked {
            return (firstTracked, .trackedByGit)
        }

        if let projectRoot {
            let firstInside = Self.isInside(first, projectRoot)
            let secondInside = Self.isInside(second, projectRoot)
            if firstInside != secondInside {
                return (firstInside, .insideProject)
            }
        }

        return nil
    }

    /// `false` for a file in no repository, which is an answer; `nil` when git could not
    /// give one.
    private func isTracked(_ url: URL) async -> Bool? {
        guard let root = await gitService.findRepositoryRoot(for: url.deletingLastPathComponent()) else {
            return false
        }
        return await gitService.isTracked(url, repositoryRoot: root)
    }

    private static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let folderPath = folder.standardizedFileURL.path
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }
}
