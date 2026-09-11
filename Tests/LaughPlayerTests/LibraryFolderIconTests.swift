import XCTest
@testable import LaughPlayer

final class LibraryFolderIconTests: XCTestCase {
    func testPrefersFinderIconWhenCustomFlagSet() {
        XCTAssertTrue(
            LibraryFolderIcon.prefersFinderIcon(
                directoryURL: URL(fileURLWithPath: "/tmp/My Pictures"),
                hasIconResourceFile: false,
                finderInfoFlags: LibraryFolderIcon.customIconFinderFlag,
                specialDirectoryURLs: []
            )
        )
    }

    func testPrefersFinderIconWhenIconResourceFilePresent() {
        XCTAssertTrue(
            LibraryFolderIcon.prefersFinderIcon(
                directoryURL: URL(fileURLWithPath: "/tmp/My Pictures"),
                hasIconResourceFile: true,
                finderInfoFlags: nil,
                specialDirectoryURLs: []
            )
        )
    }

    func testPrefersFinderIconForSpecialDirectory() {
        let downloads = URL(fileURLWithPath: "/Users/me/Downloads")
        XCTAssertTrue(
            LibraryFolderIcon.prefersFinderIcon(
                directoryURL: downloads,
                hasIconResourceFile: false,
                finderInfoFlags: 0,
                specialDirectoryURLs: [downloads]
            )
        )
    }

    func testFallsBackToSymbolForGenericFolder() {
        XCTAssertFalse(
            LibraryFolderIcon.prefersFinderIcon(
                directoryURL: URL(fileURLWithPath: "/Users/me/Movies/Random"),
                hasIconResourceFile: false,
                finderInfoFlags: 0,
                specialDirectoryURLs: [URL(fileURLWithPath: "/Users/me/Downloads")],
                homeDirectoryURL: URL(fileURLWithPath: "/Users/me")
            )
        )
    }

    func testPrefersFinderIconForHomeDownloadsByName() {
        XCTAssertTrue(
            LibraryFolderIcon.isSpecialHomeFolder(
                directoryURL: URL(fileURLWithPath: "/Users/me/Downloads"),
                homeDirectoryURL: URL(fileURLWithPath: "/Users/me")
            )
        )
        XCTAssertFalse(
            LibraryFolderIcon.isSpecialHomeFolder(
                directoryURL: URL(fileURLWithPath: "/Users/me/Projects/Downloads"),
                homeDirectoryURL: URL(fileURLWithPath: "/Users/me")
            )
        )
    }

    func testSpecialSidebarSymbolForDownloads() {
        let symbol = LibraryFolderIcon.specialSidebarSymbol(
            for: URL(fileURLWithPath: "/Users/me/Downloads")
        )
        XCTAssertEqual(symbol, "arrow.down.circle.fill")
    }

    func testParsesFinderInfoCustomIconFlag() {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[8] = 0x04
        bytes[9] = 0x00
        let flags = LibraryFolderIcon.finderInfoFlags(fromFinderInfo: Data(bytes))
        XCTAssertEqual(flags, LibraryFolderIcon.customIconFinderFlag)
        XCTAssertTrue(((flags ?? 0) & LibraryFolderIcon.customIconFinderFlag) != 0)
    }
}
