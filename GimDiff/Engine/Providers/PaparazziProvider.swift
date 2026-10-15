//
//  PaparazziProvider.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Recognises the layout Paparazzi, the Android snapshot library, records into.
///
/// ```
/// app/src/test/kotlin/com/example/LaunchViewTest.kt
/// app/src/test/snapshots/images/
///     com.example_LaunchViewTest_pixel5.png
///     com.example_LaunchViewTest_pixel5_dark_mode.png
/// ```
///
/// Every test class of a module records into the same flat `images` folder, with the
/// package, class, method, and optional label spelled into each file name. A suite is
/// therefore a class rather than a folder, and shares its folder with every other class of
/// the module (``SnapshotSuite/sharesFolder``).
///
/// A failing run writes its images under the module's `build` folder, which discovery
/// prunes, so only recorded images are listed.
struct PaparazziProvider: SnapshotProvider {
    /// Folder Paparazzi keeps beneath a source set, holding `images` and `videos`.
    static let snapshotsFolderName = "snapshots"
    /// Folder holding the recorded images themselves.
    static let imagesFolderName = "images"
    /// Folder holding a module's source sets.
    static let sourceFolderName = "src"
    /// Separator Paparazzi puts between the package, class, method, and label.
    static let delimiter = "_"
    /// Extensions of the test sources a suite can be linked to.
    static let sourceExtensions: Set<String> = ["kt", "java"]
    /// Folders inside a source set whose subfolders spell the package.
    static let sourceRootNames: Set<String> = ["kotlin", "java"]

    /// A test class found among the project's sources.
    struct TestClass: Sendable, Equatable {
        var packageName: String
        var className: String
        var sourceURL: URL?

        /// What Paparazzi writes before the method in every file name the class records.
        var fileNamePrefix: String { packageName + delimiter + className + delimiter }
    }

    /// A recorded file name, split into the class that recorded it and the snapshot's name.
    struct RecordedName: Sendable, Equatable {
        var packageName: String
        /// The class as Paparazzi names it: `Outer$Inner` for a nested class.
        var className: String
        /// The test method, followed by the snapshot's label when it has one.
        var snapshotName: String
    }

    let id = "android.paparazzi"
    let displayName = "Paparazzi Snapshots"

    private let ignoreFilter: ProviderIgnoreFilter

    init(ignoreFilter: ProviderIgnoreFilter = ProviderIgnoreFilter()) {
        self.ignoreFilter = ignoreFilter
    }

    func canHandle(projectRoot: URL, filesystem: any FilesystemService) async -> Bool {
        let contents = try? treeContents(under: projectRoot, filesystem: filesystem, ignoring: ignoreFilter)
        return contents?.directories.contains { Self.isImagesFolder($0.pathComponents) } ?? false
    }

    func discoverSuites(in projectRoot: URL, filesystem: any FilesystemService) async throws -> [SnapshotSuite] {
        let contents = try treeContents(under: projectRoot, filesystem: filesystem, ignoring: ignoreFilter)
        let filesByParent = contents.filesByParentPath()
        let testClasses = testClassIndex(in: contents)

        var suites: [SnapshotSuite] = []

        for folder in contents.directories where Self.isImagesFolder(folder.pathComponents) {
            try Task.checkCancellation()

            let images = (filesByParent[folder.path] ?? []).filter { ImageFormat(url: $0).isRecognized }
            var itemsByClass: [String: (name: RecordedName, items: [SnapshotItem])] = [:]

            for image in images {
                let stem = image.deletingPathExtension().lastPathComponent
                // A name Paparazzi could not have written still belongs on screen, under the
                // module, rather than vanishing from the tree.
                let recorded = Self.recordedName(of: stem, among: testClasses)
                    ?? RecordedName(packageName: "", className: Self.moduleName(of: folder), snapshotName: stem)
                let key = recorded.packageName + Self.delimiter + recorded.className
                itemsByClass[key, default: (recorded, [])].items.append(
                    SnapshotItem(name: recorded.snapshotName, fileURL: image)
                )
            }

            for (key, entry) in itemsByClass {
                suites.append(
                    SnapshotSuite(
                        id: folder.path + "/" + key,
                        name: entry.name.className,
                        sourceCodeURL: Self.sourceFile(for: entry.name, among: testClasses),
                        snapshotsFolderURL: folder,
                        snapshots: entry.items.sorted { $0.name < $1.name },
                        providerId: id,
                        sharesFolder: true
                    )
                )
            }
        }

        return suites.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    func resolveSourceFile(
        for suiteName: String,
        in projectRoot: URL,
        filesystem: any FilesystemService
    ) async -> URL? {
        guard let contents = try? treeContents(
            under: projectRoot,
            filesystem: filesystem,
            ignoring: ignoreFilter
        ) else { return nil }

        let outerName = Self.outerClassName(suiteName)
        return testClassIndex(in: contents)
            .filter { $0.className == outerName }
            .compactMap(\.sourceURL)
            .min { $0.pathComponents.count < $1.pathComponents.count }
    }

    // MARK: - Naming

    /// Whether a folder's path ends in `src/<source set>/snapshots/images`.
    ///
    /// The whole tail is required, not the last folder alone: `images` is far too common a
    /// name to claim a project on.
    static func isImagesFolder(_ components: [String]) -> Bool {
        let tail = components.suffix(4)
        guard tail.count == 4 else { return false }
        let folders = Array(tail)
        return folders[0] == sourceFolderName
            && folders[2] == snapshotsFolderName
            && folders[3] == imagesFolderName
    }

    /// Splits a recorded file's name into its package, class, and snapshot name.
    ///
    /// Java allows an underscore in a package or class name, so the separator alone cannot
    /// say where the class ends. A test class the sources declare is matched first, the
    /// longest one winning; failing that, the package is everything before the first
    /// separator and the class everything before the second. `nil` when the name has too
    /// few parts to be Paparazzi's at all.
    static func recordedName(of stem: String, among testClasses: [TestClass] = []) -> RecordedName? {
        let declared = testClasses
            .filter { stem.hasPrefix($0.fileNamePrefix) && stem.count > $0.fileNamePrefix.count }
            .max { $0.fileNamePrefix.count < $1.fileNamePrefix.count }
        if let declared {
            return RecordedName(
                packageName: declared.packageName,
                className: declared.className,
                snapshotName: String(stem.dropFirst(declared.fileNamePrefix.count))
            )
        }

        let parts = stem.components(separatedBy: delimiter)
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        let snapshotName = parts.dropFirst(2).joined(separator: delimiter)
        guard !snapshotName.isEmpty else { return nil }
        return RecordedName(packageName: parts[0], className: parts[1], snapshotName: snapshotName)
    }

    /// The class a nested class is declared in, which is what names its source file.
    static func outerClassName(_ className: String) -> String {
        String(className.prefix { $0 != "$" })
    }

    /// The source declaring `name`'s class, matched on package as well as class name.
    private static func sourceFile(for name: RecordedName, among testClasses: [TestClass]) -> URL? {
        let outerName = outerClassName(name.className)
        return testClasses.first {
            $0.packageName == name.packageName && $0.className == outerName
        }?.sourceURL
    }

    /// The module an images folder belongs to: the folder above `src`.
    private static func moduleName(of imagesFolder: URL) -> String {
        imagesFolder
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
    }

    /// Whether a source set holds tests: `test`, `testDebug`, or a multiplatform module's
    /// `androidUnitTest`. Production code is left out so a class it shares a name with is
    /// never offered as a suite's test file.
    static func isTestSourceSet(_ name: String) -> Bool {
        name.range(of: "test", options: .caseInsensitive) != nil
    }

    /// Every Kotlin or Java file beneath a test source set's `kotlin` or `java` folder, with the
    /// package its folders spell.
    ///
    /// The package is read from the path, not the source: Kotlin lets the two differ, but a
    /// test class almost never does, and reading every file would cost more than a mismatch.
    private func testClassIndex(in contents: ProjectTreeContents) -> [TestClass] {
        contents.files.compactMap { file in
            guard Self.sourceExtensions.contains(file.pathExtension.lowercased()) else { return nil }
            let folders = file.deletingLastPathComponent().pathComponents
            guard let sourceIndex = folders.lastIndex(of: Self.sourceFolderName),
                  sourceIndex + 2 < folders.endIndex,
                  Self.isTestSourceSet(folders[sourceIndex + 1]),
                  Self.sourceRootNames.contains(folders[sourceIndex + 2])
            else { return nil }

            return TestClass(
                packageName: folders[(sourceIndex + 3)...].joined(separator: "."),
                className: file.deletingPathExtension().lastPathComponent,
                sourceURL: file
            )
        }
    }
}
