import Foundation
import XCTest
@testable import LaughPlayer

/// Scoping folder management to the folder a file was opened from — including files that
/// live nowhere near a library root, which is where Recents and Finder opens land.
final class MediaLibraryRootMatchTests: XCTestCase {
    private func root(_ path: String, id: String) -> MediaLibraryRoot {
        MediaLibraryRoot(
            id: id,
            displayName: (path as NSString).lastPathComponent,
            directoryURL: URL(fileURLWithPath: path, isDirectory: true),
            isUserAdded: false
        )
    }

    func testFolderInsideARootMatchesIt() {
        let roots = [root("/Users/me/Movies", id: "movies")]
        let match = MediaLibraryController.root(
            containing: URL(fileURLWithPath: "/Users/me/Movies/Trips", isDirectory: true),
            in: roots
        )
        XCTAssertEqual(match?.id, "movies")
    }

    func testRootItselfMatches() {
        let roots = [root("/Users/me/Movies", id: "movies")]
        let match = MediaLibraryController.root(
            containing: URL(fileURLWithPath: "/Users/me/Movies", isDirectory: true),
            in: roots
        )
        XCTAssertEqual(match?.id, "movies")
    }

    func testDeepestRootWins() {
        let roots = [
            root("/Users/me/Movies", id: "movies"),
            root("/Users/me/Movies/Trips", id: "trips")
        ]
        let match = MediaLibraryController.root(
            containing: URL(fileURLWithPath: "/Users/me/Movies/Trips/2026", isDirectory: true),
            in: roots
        )
        XCTAssertEqual(match?.id, "trips")
    }

    /// The bug this fixes: default roots are Movies and ~/Videos, so anything on the
    /// Desktop matched nothing and the browser fell back to an unrelated root.
    func testFolderOutsideEveryRootMatchesNothing() {
        let roots = [root("/Users/me/Movies", id: "movies"), root("/Users/me/Videos", id: "videos")]
        XCTAssertNil(
            MediaLibraryController.root(
                containing: URL(fileURLWithPath: "/Users/me/Desktop/photos", isDirectory: true),
                in: roots
            )
        )
    }

    /// Prefix matching must respect path boundaries, or "/Users/me/Videos-old" would be
    /// treated as living inside "/Users/me/Videos".
    func testSiblingWithASharedNamePrefixDoesNotMatch() {
        let roots = [root("/Users/me/Videos", id: "videos")]
        XCTAssertNil(
            MediaLibraryController.root(
                containing: URL(fileURLWithPath: "/Users/me/Videos-old", isDirectory: true),
                in: roots
            )
        )
    }
}

final class MediaLibraryBreadcrumbTrailTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    func testTrailInsideHomeIsAnchoredAtHome() {
        let trail = MediaLibraryController.folderBreadcrumbTrail(
            for: URL(fileURLWithPath: "/Users/me/Desktop/photos", isDirectory: true),
            home: home
        )
        XCTAssertEqual(trail.map(\.title), ["me", "Desktop", "photos"])
        XCTAssertEqual(trail.map { $0.url.path }, ["/Users/me", "/Users/me/Desktop", "/Users/me/Desktop/photos"])
    }

    func testHomeItselfIsASingleCrumb() {
        let trail = MediaLibraryController.folderBreadcrumbTrail(for: home, home: home)
        XCTAssertEqual(trail.map(\.title), ["me"])
    }

    func testTrailOutsideHomeWalksFromTheFilesystemRoot() {
        let trail = MediaLibraryController.folderBreadcrumbTrail(
            for: URL(fileURLWithPath: "/Volumes/Photos/2026", isDirectory: true),
            home: home
        )
        XCTAssertEqual(trail.map(\.title), ["Computer", "Volumes", "Photos", "2026"])
        XCTAssertEqual(trail.first?.url.path, "/")
    }

    /// A folder whose name merely starts with the home path is not inside it.
    func testHomeNamePrefixIsNotTreatedAsInsideHome() {
        let trail = MediaLibraryController.folderBreadcrumbTrail(
            for: URL(fileURLWithPath: "/Users/mexico/pics", isDirectory: true),
            home: home
        )
        XCTAssertEqual(trail.map(\.title), ["Computer", "Users", "mexico", "pics"])
    }
}

final class MediaLibraryRevealFolderTests: XCTestCase {
    /// Reveal a folder that no library root covers: browse should be showing that folder's
    /// contents, with no sidebar row selected.
    func testRevealingAFolderOutsideEveryRootBrowsesItDirectly() throws {
        let folder = try makeFolder(named: "reveal-outside", files: ["a.png", "b.png"])
        let controller = MediaLibraryController()

        controller.revealFolder(folder)

        XCTAssertEqual(controller.sidebarMode, .folder(root: nil))
        XCTAssertEqual(
            controller.currentDirectoryURL?.resolvingSymlinksInPath().standardizedFileURL,
            folder.resolvingSymlinksInPath().standardizedFileURL
        )
        XCTAssertEqual(controller.selectedSidebarRow, MediaLibraryController.noSelectionRow)
        XCTAssertEqual(Set(controller.displayedEntries.map(\.name)), ["a.png", "b.png"])
        XCTAssertTrue(controller.showsFolderBrowseChrome, "folder toolbar belongs here too")
        XCTAssertFalse(controller.showsBrowsePlaceholder, "this is a real listing, not the drop hint")
    }

    /// A root-less browse has no sidebar row to validate, so the selection check that runs
    /// on every root reload must not mistake it for a stale selection and clear it.
    func testRootReloadKeepsARootLessBrowse() throws {
        let folder = try makeFolder(named: "reveal-survives", files: ["a.png"])
        let controller = MediaLibraryController()
        controller.revealFolder(folder)

        controller.reloadRoots()

        XCTAssertEqual(controller.sidebarMode, .folder(root: nil))
        XCTAssertEqual(
            controller.currentDirectoryURL?.resolvingSymlinksInPath().standardizedFileURL,
            folder.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    func testRootLessBrowseCanNavigateIntoSubfoldersAndBack() throws {
        let folder = try makeFolder(named: "reveal-nav", files: ["a.png"])
        let child = folder.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let controller = MediaLibraryController()
        controller.revealFolder(folder)

        controller.openFolder(child)
        XCTAssertEqual(
            controller.currentDirectoryURL?.lastPathComponent,
            "inner",
            "navigation must work without a root above it"
        )
        XCTAssertTrue(controller.canGoBack)

        controller.goBack()
        XCTAssertEqual(controller.currentDirectoryURL?.lastPathComponent, folder.lastPathComponent)
    }

    func testBreadcrumbsDescribeARootLessFolder() throws {
        let folder = try makeFolder(named: "reveal-crumbs", files: [])
        let controller = MediaLibraryController()
        controller.revealFolder(folder)

        let crumbs = controller.breadcrumbComponents()
        XCTAssertEqual(crumbs.last?.title, folder.lastPathComponent)
        XCTAssertGreaterThan(crumbs.count, 1, "the trail should be walkable, not a single crumb")
        XCTAssertTrue(crumbs.allSatisfy { $0.url != nil }, "every crumb should be clickable")
    }

    // MARK: - Helpers

    private func makeFolder(named name: String, files: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        for file in files {
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent(file))
        }
        return folder
    }
}
