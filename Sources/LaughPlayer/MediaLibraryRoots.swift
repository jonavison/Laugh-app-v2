import Foundation

struct MediaLibraryRoot: Equatable {
    let id: String
    let displayName: String
    let directoryURL: URL
    let isUserAdded: Bool
}

enum MediaLibraryRoots {
    static func allRoots() -> [MediaLibraryRoot] {
        var roots = defaultRoots()
        let userRoots = LibraryRootsStore.shared.loadUserRoots()
        for user in userRoots {
            let path = user.directoryURL.standardizedFileURL
            if roots.contains(where: { $0.directoryURL.standardizedFileURL == path }) {
                continue
            }
            roots.append(user)
        }
        return roots
    }

    static func defaultRoots() -> [MediaLibraryRoot] {
        var roots: [MediaLibraryRoot] = []

        if let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            roots.append(MediaLibraryRoot(id: "movies", displayName: "Movies", directoryURL: movies, isUserAdded: false))
        }

        let homeVideos = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Videos", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: homeVideos.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let alreadyListed = roots.contains { $0.directoryURL.standardizedFileURL == homeVideos.standardizedFileURL }
            if !alreadyListed {
                roots.append(MediaLibraryRoot(id: "videos", displayName: "Videos", directoryURL: homeVideos, isUserAdded: false))
            }
        }

        return roots
    }
}
