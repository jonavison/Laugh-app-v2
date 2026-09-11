import XCTest
@testable import LaughPlayer

final class FolderPlaybackNeighborsTests: XCTestCase {
    func testNameSortNeighborsSkipMissingEnds() {
        let dir = URL(fileURLWithPath: "/Shows/Season1", isDirectory: true)
        let ep1 = dir.appendingPathComponent("Show - S01E01.mkv")
        let ep2 = dir.appendingPathComponent("Show - S01E02.mkv")
        let ep3 = dir.appendingPathComponent("Show - S01E03.mkv")
        let entries = [ep1, ep2, ep3].map { url in
            LibraryBrowseEntry(
                kind: .media(LibraryMediaFile(url: url, kind: .video)),
                name: url.lastPathComponent,
                dateModified: nil,
                dateAdded: nil,
                size: nil
            )
        }

        let atFirst = FolderPlaybackNeighbors.neighbors(
            around: ep1,
            matchingKind: .video,
            sort: .default,
            entriesInDirectory: { _ in entries }
        )
        XCTAssertNil(atFirst.previous)
        XCTAssertEqual(atFirst.next, ep2.standardizedFileURL)

        let atMiddle = FolderPlaybackNeighbors.neighbors(
            around: ep2,
            matchingKind: .video,
            sort: .default,
            entriesInDirectory: { _ in entries }
        )
        XCTAssertEqual(atMiddle.previous, ep1.standardizedFileURL)
        XCTAssertEqual(atMiddle.next, ep3.standardizedFileURL)

        let atLast = FolderPlaybackNeighbors.neighbors(
            around: ep3,
            matchingKind: .video,
            sort: .default,
            entriesInDirectory: { _ in entries }
        )
        XCTAssertEqual(atLast.previous, ep2.standardizedFileURL)
        XCTAssertNil(atLast.next)
    }

    func testIgnoresOtherMediaKinds() {
        let dir = URL(fileURLWithPath: "/Mix", isDirectory: true)
        let video = dir.appendingPathComponent("a.mkv")
        let image = dir.appendingPathComponent("b.jpg")
        let entries = [
            LibraryBrowseEntry(
                kind: .media(LibraryMediaFile(url: video, kind: .video)),
                name: "a.mkv",
                dateModified: nil,
                dateAdded: nil,
                size: nil
            ),
            LibraryBrowseEntry(
                kind: .media(LibraryMediaFile(url: image, kind: .image)),
                name: "b.jpg",
                dateModified: nil,
                dateAdded: nil,
                size: nil
            )
        ]
        let result = FolderPlaybackNeighbors.neighbors(
            around: video,
            matchingKind: .video,
            sort: .default,
            entriesInDirectory: { _ in entries }
        )
        XCTAssertNil(result.previous)
        XCTAssertNil(result.next)
    }
}
