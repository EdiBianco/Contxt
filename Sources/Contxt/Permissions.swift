// Contxt's only TCC need is Files & Folders (Desktop/Documents/Downloads
// as drop targets). The hotkey is Carbon RegisterEventHotKey, so Input
// Monitoring / Accessibility are not required.

import AppKit

enum Permissions {
    private static let filesAndFoldersURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

    static func isPermissionError(_ error: Error) -> Bool {
        let e = error as NSError
        switch e.domain {
        case NSCocoaErrorDomain:
            return e.code == CocoaError.fileReadNoPermission.rawValue
                || e.code == CocoaError.fileWriteNoPermission.rawValue
        case NSPOSIXErrorDomain:
            return e.code == Int(EPERM) || e.code == Int(EACCES)
        default:
            return false
        }
    }

    /// Listing a protected folder makes macOS show its one-time access
    /// prompt; a permission error afterwards means it was denied. Blocks
    /// while the prompt is up, so call off the main thread.
    private static func deniedFolders(in destinations: [Destination]) -> [String] {
        destinations.compactMap { destination in
            guard case .folder(_, let label, let path, _) = destination else { return nil }
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: path)
                return nil
            } catch {
                return isPermissionError(error) ? label : nil
            }
        }
    }

    static func checkAndPrompt() {
        let destinations = DestinationStore.shared.destinations
        DispatchQueue.global(qos: .userInitiated).async {
            let denied = deniedFolders(in: destinations)
            guard !denied.isEmpty else { return }
            DispatchQueue.main.async { promptOpenSettings(for: denied) }
        }
    }

    static func promptOpenSettings(for folders: [String]) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Contxt needs folder access"
        alert.informativeText = "Allow Contxt to access \(folders.joined(separator: ", ")) so it can move files there. Turn Contxt on under Files & Folders."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: filesAndFoldersURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
