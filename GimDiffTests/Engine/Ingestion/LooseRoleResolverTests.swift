//
//  LooseRoleResolverTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Deciding the sides of a loose pair")
struct LooseRoleResolverTests {
    private static let repository = URL(fileURLWithPath: "/Users/david/Dev/Demo")
    private static let recorded = URL(fileURLWithPath: "/Users/david/Dev/Demo/__Snapshots__/home.png")
    private static let rendered = URL(fileURLWithPath: "/private/tmp/HomeTests/home.png")

    private func resolver(tracked: Set<URL> = [], trackingFails: Bool = false) -> LooseRoleResolver {
        var git = StubGitService(repositoryRoot: Self.repository)
        git.trackedFiles = tracked
        git.trackingFails = trackingFails
        return LooseRoleResolver(gitService: git)
    }

    @Test("A tracked file is the baseline, even when it was listed second")
    func trackedFileIsTheBaseline() async {
        let resolution = await resolver(tracked: [Self.recorded]).resolve(
            baseline: Self.rendered,
            candidate: Self.recorded,
            rolesAreStated: false,
            projectRoot: nil
        )

        #expect(resolution.baselineURL == Self.recorded)
        #expect(resolution.candidateURL == Self.rendered)
        #expect(resolution.certainty == .inferred(.trackedByGit, swapped: true))
    }

    @Test("The files outrank labels a log got the wrong way round")
    func filesOverruleMisreadLabels() async {
        let resolution = await resolver(tracked: [Self.recorded]).resolve(
            baseline: Self.rendered,
            candidate: Self.recorded,
            rolesAreStated: true,
            projectRoot: nil
        )

        #expect(resolution.baselineURL == Self.recorded)
        #expect(resolution.certainty == .inferred(.trackedByGit, swapped: true))
    }

    @Test("Files that agree with the labels leave them stated")
    func agreementKeepsTheLabels() async {
        let resolution = await resolver(tracked: [Self.recorded]).resolve(
            baseline: Self.recorded,
            candidate: Self.rendered,
            rolesAreStated: true,
            projectRoot: nil
        )

        #expect(resolution.baselineURL == Self.recorded)
        #expect(resolution.certainty == .stated)
    }

    @Test("Files that agree with an unlabelled order make it an inference, not a guess")
    func agreementWithOrderIsInferred() async {
        let resolution = await resolver(tracked: [Self.recorded]).resolve(
            baseline: Self.recorded,
            candidate: Self.rendered,
            rolesAreStated: false,
            projectRoot: nil
        )

        #expect(resolution.certainty == .inferred(.trackedByGit, swapped: false))
    }

    @Test("With Git silent, the image inside the open project is the baseline")
    func projectDecidesWhenGitCannot() async {
        let resolution = await resolver().resolve(
            baseline: Self.rendered,
            candidate: Self.recorded,
            rolesAreStated: false,
            projectRoot: Self.repository
        )

        #expect(resolution.baselineURL == Self.recorded)
        #expect(resolution.certainty == .inferred(.insideProject, swapped: true))
    }

    @Test("Git that cannot answer is no evidence either way")
    func failedGitIsNoEvidence() async {
        let resolution = await resolver(tracked: [Self.recorded], trackingFails: true).resolve(
            baseline: Self.rendered,
            candidate: Self.recorded,
            rolesAreStated: false,
            projectRoot: nil
        )

        #expect(resolution.baselineURL == Self.rendered)
        #expect(resolution.certainty == .unknown)
    }

    @Test("Two files nothing tells apart keep the source's order and are reported as unknown")
    func indistinguishableFilesAreUnknown() async {
        let desktop = URL(fileURLWithPath: "/Users/david/Desktop/a.png")
        let downloads = URL(fileURLWithPath: "/Users/david/Downloads/b.png")

        let resolution = await resolver().resolve(
            baseline: desktop,
            candidate: downloads,
            rolesAreStated: false,
            projectRoot: Self.repository
        )

        #expect(resolution.baselineURL == desktop)
        #expect(resolution.candidateURL == downloads)
        #expect(resolution.certainty == .unknown)
    }

    @Test("Two files nothing tells apart keep the labels a log gave them")
    func indistinguishableFilesKeepStatedLabels() async {
        let resolution = await resolver().resolve(
            baseline: Self.rendered,
            candidate: Self.recorded,
            rolesAreStated: true,
            projectRoot: nil
        )

        #expect(resolution.baselineURL == Self.rendered)
        #expect(resolution.certainty == .stated)
    }

    @Test("A folder that merely shares a prefix with the project is outside it")
    func siblingFolderIsOutsideTheProject() async {
        let sibling = URL(fileURLWithPath: "/Users/david/Dev/Demo-old/__Snapshots__/home.png")

        let resolution = await resolver().resolve(
            baseline: sibling,
            candidate: Self.recorded,
            rolesAreStated: false,
            projectRoot: Self.repository
        )

        #expect(resolution.baselineURL == Self.recorded)
        #expect(resolution.certainty == .inferred(.insideProject, swapped: true))
    }
}
