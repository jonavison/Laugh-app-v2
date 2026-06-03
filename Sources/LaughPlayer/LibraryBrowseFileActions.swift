import AppKit
import Foundation

enum LibraryBrowseFileActions {
    static func itemURL(for entry: LibraryBrowseEntry) -> URL? {
        switch entry.kind {
        case .folder(let url):
            return url
        case .media(let file):
            return file.url
        }
    }

    static func showInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @discardableResult
    static func renameItem(at url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibraryBrowseFileError.emptyName
        }
        guard trimmed != ".." && trimmed != "." else {
            throw LibraryBrowseFileError.invalidName
        }
        if trimmed.contains("/") {
            throw LibraryBrowseFileError.invalidName
        }

        var finalName = trimmed
        let originalExt = url.pathExtension
        if !originalExt.isEmpty {
            let typedExt = (trimmed as NSString).pathExtension
            if typedExt.isEmpty {
                finalName = "\(trimmed).\(originalExt)"
            }
        }

        let destination = url.deletingLastPathComponent().appendingPathComponent(finalName)
        guard destination.standardizedFileURL != url.standardizedFileURL else {
            return url
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw LibraryBrowseFileError.nameAlreadyExists
        }

        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    static func moveToTrash(url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func confirmRemove(itemName: String, isDirectory: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let kind = isDirectory ? "folder" : "file"
        alert.messageText = "Remove “\(itemName)”?"
        alert.informativeText = "This \(kind) will be moved to the Trash."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove")
        if let removeButton = alert.buttons.last {
            removeButton.hasDestructiveAction = true
        }
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func promptRename(currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Rename")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = currentName
        field.selectText(nil)
        alert.accessoryView = field

        guard alert.runModal() == .alertSecondButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func presentError(_ error: Error, title: String = "Could Not Complete Action") {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        if let libraryError = error as? LibraryBrowseFileError {
            alert.informativeText = libraryError.localizedDescription
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum LibraryBrowseFileError: LocalizedError {
    case emptyName
    case invalidName
    case nameAlreadyExists

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Name cannot be empty."
        case .invalidName:
            return "Name is not valid."
        case .nameAlreadyExists:
            return "An item with that name already exists in this folder."
        }
    }
}
