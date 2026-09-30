//
//  DerivedDataLocator.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Finds a project's test results among Xcode's derived data.
///
/// Each workspace Xcode has built owns a folder there, named after a hash of its path.
/// The hash is not reproduced: the folder's `info.plist` records the workspace it belongs
/// to, and reading that back is what Xcode itself supports.
struct DerivedDataLocator: TestResultLocating {
    /// Where Xcode keeps derived data unless told otherwise.
    static let defaultDerivedDataURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
    /// Xcode's preference for a derived data folder of the user's choosing.
    static let xcodeDefaultsDomain = "com.apple.dt.Xcode"
    static let customLocationKey = "IDECustomDerivedDataLocation"

    static let workspaceInfoFileName = "info.plist"
    static let workspacePathKey = "WorkspacePath"
    static let testLogsPath = "Logs/Test"
    static let resultBundleExtension = "xcresult"
    static let resultInfoFileName = "Info.plist"
    static let resultCreationDateKey = "dateCreated"
    /// Workspaces that are documents inside the folder they build, as opposed to a Swift
    /// package, where the folder itself is what Xcode opens.
    static let workspaceDocumentExtensions: Set<String> = ["xcodeproj", "xcworkspace"]

    private let derivedDataURL: URL

    init(derivedDataURL: URL = DerivedDataLocator.preferredDerivedDataURL) {
        self.derivedDataURL = derivedDataURL
    }

    /// The folder Xcode is set to use on this machine.
    ///
    /// A relative custom location is resolved by Xcode against each workspace, so there is
    /// no single folder to look in and the default is kept.
    static var preferredDerivedDataURL: URL {
        guard let custom = UserDefaults(suiteName: xcodeDefaultsDomain)?.string(forKey: customLocationKey),
              custom.hasPrefix("/") || custom.hasPrefix("~")
        else { return defaultDerivedDataURL }

        return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
    }

    func latestResultBundle(forProjectAt rootURL: URL, gitRootURL: URL?) -> URL? {
        workspaceFolders(forProjectAt: rootURL, gitRootURL: gitRootURL)
            .flatMap(resultBundles(in:))
            .max { $0.created < $1.created }?
            .url
    }

    func resultDirectories(forProjectAt rootURL: URL, gitRootURL: URL?) -> [URL] {
        workspaceFolders(forProjectAt: rootURL, gitRootURL: gitRootURL)
            .map { $0.appendingPathComponent(Self.testLogsPath, isDirectory: true) }
            .filter { url in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
    }

    /// The derived data folders of every workspace that builds the project.
    private func workspaceFolders(forProjectAt rootURL: URL, gitRootURL: URL?) -> [URL] {
        let root = Self.canonicalPath(of: rootURL)
        let gitRoot = gitRootURL.map(Self.canonicalPath(of:))
        let folders = (try? fileManager.contentsOfDirectory(
            at: derivedDataURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return folders.filter { folder in
            guard let workspace = workspaceURL(of: folder) else { return false }
            return Self.workspace(workspace, belongsToProjectAt: root, gitRoot: gitRoot)
        }
    }

    // MARK: - Workspaces

    private var fileManager: FileManager { .default }

    private func workspaceURL(of folder: URL) -> URL? {
        let info = folder.appendingPathComponent(Self.workspaceInfoFileName)
        guard let path = Self.propertyList(at: info)?[Self.workspacePathKey] as? String else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Whether `workspace` builds the project at `root`.
    ///
    /// Either can sit inside the other: a project opened on the repository holds its
    /// workspaces, and one opened on a single snapshot folder is held by the folder its
    /// workspace builds. Failing both, sharing a working tree is enough.
    private static func workspace(_ workspace: URL, belongsToProjectAt root: String, gitRoot: String?) -> Bool {
        let document = canonicalPath(of: workspace)
        let built = workspaceDocumentExtensions.contains(workspace.pathExtension.lowercased())
            ? canonicalPath(of: workspace.deletingLastPathComponent())
            : document

        if isPath(document, within: root) || isPath(root, within: built) { return true }
        guard let gitRoot else { return false }
        return isPath(document, within: gitRoot)
    }

    // MARK: - Result bundles

    private func resultBundles(in folder: URL) -> [(url: URL, created: Date)] {
        let logs = folder.appendingPathComponent(Self.testLogsPath, isDirectory: true)
        let entries = (try? fileManager.contentsOfDirectory(
            at: logs,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries
            .filter { $0.pathExtension.lowercased() == Self.resultBundleExtension }
            .map { ($0, creationDate(ofBundle: $0)) }
    }

    /// When the run started, as the bundle records it.
    ///
    /// Read from the bundle rather than from its name or the volume: the name's format is
    /// Xcode's to change, and a bundle copied or restored from a backup is dated by the
    /// volume from the day it was copied.
    private func creationDate(ofBundle bundle: URL) -> Date {
        let info = bundle.appendingPathComponent(Self.resultInfoFileName)
        if let recorded = Self.propertyList(at: info)?[Self.resultCreationDateKey] as? Date {
            return recorded
        }
        return (try? bundle.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
    }

    // MARK: - Reading

    private static func propertyList(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// `/tmp` and `/private/tmp` are one folder, and a project reached through a symlink is
    /// recorded by Xcode under whichever spelling it was opened with.
    private static func canonicalPath(of url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func isPath(_ path: String, within folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}
