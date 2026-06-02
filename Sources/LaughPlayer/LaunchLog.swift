import Foundation

enum LaunchLog {
    static func emit(_ message: String) {
        let line = "[LaughPlayer] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
