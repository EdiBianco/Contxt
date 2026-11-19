// Ported from the Electron prototype's src/main/actions.ts.

import AppKit

enum DropActions {
    private static func uniqueDestPath(destDir: String, fileName: String) -> String {
        let fm = FileManager.default
        var candidate = "\(destDir)/\(fileName)"
        if !fm.fileExists(atPath: candidate) { return candidate }

        let ext = (fileName as NSString).pathExtension
        let stem = ext.isEmpty ? fileName : (fileName as NSString).deletingPathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        var i = 2
        while true {
            candidate = "\(destDir)/\(stem) \(i)\(suffix)"
            if !fm.fileExists(atPath: candidate) { return candidate }
            i += 1
        }
    }

    /// `mode` is the folder's default action; holding Option uses the other one.
    static func dropOnFolder(destinationPath: String, filePaths: [String], altKeyHeld: Bool, mode: DropMode) {
        let fm = FileManager.default
        let effective = altKeyHeld ? mode.inverted : mode
        var permissionDenied = false

        for sourcePath in filePaths {
            let fileName = (sourcePath as NSString).lastPathComponent
            let destPath = uniqueDestPath(destDir: destinationPath, fileName: fileName)

            do {
                switch effective {
                case .move: try fm.moveItem(atPath: sourcePath, toPath: destPath)
                case .copy: try fm.copyItem(atPath: sourcePath, toPath: destPath)
                }
            } catch {
                contxtLog("drop-on-folder failed for \(sourcePath): \(error)")
                if Permissions.isPermissionError(error) { permissionDenied = true }
            }
        }

        if permissionDenied {
            let folder = (destinationPath as NSString).lastPathComponent
            DispatchQueue.main.async { Permissions.promptOpenSettings(for: [folder]) }
        }
    }

    /// Runs the script with the dropped file paths as arguments. Executable
    /// files run directly (shebang); anything else is run through zsh.
    static func dropOnScript(scriptPath: String, filePaths: [String]) {
        let process = Process()
        if FileManager.default.isExecutableFile(atPath: scriptPath) {
            process.executableURL = URL(fileURLWithPath: scriptPath)
            process.arguments = filePaths
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [scriptPath] + filePaths
        }
        process.currentDirectoryURL = URL(fileURLWithPath: (scriptPath as NSString).deletingLastPathComponent)

        process.terminationHandler = { finished in
            contxtLog("script \(scriptPath) exited with status \(finished.terminationStatus)")
        }
        do {
            try process.run()
        } catch {
            contxtLog("script \(scriptPath) failed to start: \(error)")
        }
    }

    static func dropOnApp(appPath: String, filePaths: [String]) {
        let appURL = URL(fileURLWithPath: appPath)
        let fileURLs = filePaths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.open(fileURLs, withApplicationAt: appURL, configuration: .init()) { _, error in
            if let error {
                contxtLog("drop-on-app failed: \(error)")
            }
        }
    }

    /// Runs a Shortcuts shortcut with the dropped files as its input.
    static func dropOnShortcut(name: String, filePaths: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name] + filePaths.flatMap { ["--input-path", $0] }
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { finished in
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            contxtLog("shortcut '\(name)' exited with status \(finished.terminationStatus) \(message)")
        }
        do {
            try process.run()
        } catch {
            contxtLog("shortcut '\(name)' failed to start: \(error)")
        }
    }

    /// WhatsApp and Telegram have no share API that takes a recipient plus
    /// files, so open the chat and leave the files on the pasteboard for Cmd+V.
    private static func dropOnChatApp(_ target: ContactTarget, filePaths: [String]) {
        let appName = target.channel == .telegram ? "Telegram" : "WhatsApp"
        guard let phone = target.phone else {
            Toast.show("No phone number saved for this contact")
            return
        }
        let digits = phone.filter(\.isNumber)
        let link = target.channel == .telegram ? "tg://resolve?phone=\(digits)" : "whatsapp://send?phone=\(digits)"
        guard let url = URL(string: link), NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            Toast.show("\(appName) isn't installed")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(filePaths.map { URL(fileURLWithPath: $0) as NSURL })
        NSWorkspace.shared.open(url)
        Toast.show("Files copied. Press \u{2318}V in the \(appName) chat to attach them")
    }

    /// Opens Messages or Mail with the files attached, addressed to the contact.
    static func dropOnContact(_ target: ContactTarget, filePaths: [String]) {
        if target.channel == .whatsapp || target.channel == .telegram {
            dropOnChatApp(target, filePaths: filePaths)
            return
        }
        let name: NSSharingService.Name = target.channel == .email ? .composeEmail : .composeMessage
        let recipient = target.channel == .email ? target.email : (target.phone ?? target.email)
        share(filePaths, via: name, recipient: recipient)
    }

    static func dropOnAction(_ action: CommonAction, filePaths: [String]) {
        switch action {
        case .composeMessage:
            share(filePaths, via: .composeMessage, recipient: nil)
        case .composeEmail:
            share(filePaths, via: .composeEmail, recipient: nil)
        case .importPhotos:
            dropOnApp(appPath: "/System/Applications/Photos.app", filePaths: filePaths)
        case .trash:
            for path in filePaths {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                } catch {
                    contxtLog("trash failed for \(path): \(error)")
                }
            }
        }
    }

    private static func share(_ filePaths: [String], via name: NSSharingService.Name, recipient: String?) {
        guard let service = NSSharingService(named: name) else {
            contxtLog("sharing service \(name.rawValue) unavailable")
            return
        }
        if let recipient { service.recipients = [recipient] }
        let items = filePaths.map { URL(fileURLWithPath: $0) }
        guard service.canPerform(withItems: items) else {
            contxtLog("sharing service \(name.rawValue) cannot take these items")
            return
        }
        service.perform(withItems: items)
    }
}
