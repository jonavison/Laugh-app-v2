import XCTest
@testable import LaughPlayer

final class LibraryFolderSortStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "LibraryFolderSortStoreTests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testUnresolvedFolderFallsBackToNameSort() {
        let url = URL(fileURLWithPath: "/tmp/Downloads")
        XCTAssertEqual(
            LibraryFolderSortStore.resolvedSort(for: url, defaults: defaults),
            .default
        )
    }

    func testRemembersSortPerFolderIndependently() {
        let downloads = URL(fileURLWithPath: "/tmp/Downloads")
        let season = URL(fileURLWithPath: "/tmp/Downloads/Rings S01")
        let dateSort = LibraryBrowseSort(key: .dateModified, direction: .descending)

        LibraryFolderSortStore.setSort(dateSort, for: downloads, defaults: defaults)

        XCTAssertEqual(
            LibraryFolderSortStore.resolvedSort(for: downloads, defaults: defaults),
            dateSort
        )
        XCTAssertEqual(
            LibraryFolderSortStore.resolvedSort(for: season, defaults: defaults),
            .default,
            "Child folders keep Name until the user sets a sort there"
        )

        let nameSort = LibraryBrowseSort(key: .name, direction: .ascending)
        LibraryFolderSortStore.setSort(nameSort, for: season, defaults: defaults)
        XCTAssertEqual(
            LibraryFolderSortStore.resolvedSort(for: season, defaults: defaults),
            nameSort
        )
        XCTAssertEqual(
            LibraryFolderSortStore.resolvedSort(for: downloads, defaults: defaults),
            dateSort,
            "Parent sort is unchanged when a child is customized"
        )
    }
}
