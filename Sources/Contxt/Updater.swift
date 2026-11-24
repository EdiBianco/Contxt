// Checks GitHub for a newer release, downloads and verifies it in the
// background, then swaps the app bundle and relaunches.
//
// Safety: the downloaded app must satisfy the *running* app's designated
// requirement, which CI pins to the "Contxt Local Signing" certificate. A
// tampered or foreign build is discarded before it can be installed.

import AppKit
import Security

enum UpdateInterval: String, CaseIterable {
    case daily, weekly, monthly, never

    var title: String {
        switch self {
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .never: return "Never"
        }
    }

    var shortTitle: String {
        switch self {
        case .daily: return "Day"
        case .weekly: return "Week"
        case .monthly: return "Month"
        case .never: return "Never"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .daily: return 86_400
        case .weekly: return 7 * 86_400
        case .monthly: return 30 * 86_400
        case .never: return nil
        }
    }
}

private enum UpdateError: LocalizedError {
    case http, noAsset, badArchive, badSignature

    var errorDescription: String? {
        switch self {
        case .http: return "GitHub could not be reached"
        case .noAsset: return "The release has no macOS download"
        case .badArchive: return "The download was not a valid app"
        case .badSignature: return "The download is not signed by the Contxt identity"
        }
    }
}

final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(String)
        case ready(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Set by the app delegate: true when restarting now would not interrupt anything.
    var isSafeToRestart: () -> Bool = { true }

    private let repo = "EdiBianco/Contxt"
    private var stagedApp: URL?
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var statusText: String {
        switch state {
        case .idle:
            if let last = Preferences.shared.lastUpdateCheck {
                return "Last checked " + last.formatted(date: .abbreviated, time: .shortened)
            }
            return "Not checked yet"
        case .checking: return "Checking…"
        case .upToDate: return "You're up to date"
        case .downloading(let version): return "Downloading \(version)…"
        case .ready(let version): return "Contxt \(version) is ready to install"
        case .failed(let message): return "Couldn't update: \(message)"
        }
    }

    // MARK: - Scheduling

    func start() {
        // Leftovers from a previous install attempt are no longer needed.
        try? FileManager.default.removeItem(at: updatesDirectory)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        applyStagedIfAllowed()

        let prefs = Preferences.shared
        guard let interval = prefs.updateInterval.seconds else { return }
        if let last = prefs.lastUpdateCheck, Date().timeIntervalSince(last) < interval { return }
        check(userInitiated: false)
    }

    // MARK: - Check and download

    func check(userInitiated: Bool) {
        switch state {
        case .checking, .downloading:
            return
        case .ready(let version):
            if userInitiated { Toast.show("Contxt \(version) is ready. Use Restart to Update") }
            return
        default:
            break
        }

        setState(.checking)
        Task {
            do {
                let release = try await fetchLatest()
                DispatchQueue.main.async { Preferences.shared.lastUpdateCheck = Date() }

                if Self.isNewer(release.version, than: currentVersion) {
                    if userInitiated { Toast.show("Downloading Contxt \(release.version)…") }
                    try await stage(version: release.version, assetURL: release.assetURL)
                } else {
                    setState(.upToDate)
                    if userInitiated { Toast.show("Contxt \(currentVersion) is up to date") }
                }
            } catch {
                contxtLog("update failed: \(error)")
                setState(.failed(error.localizedDescription))
                if userInitiated { Toast.show("Update failed: \(error.localizedDescription)") }
            }
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let assets: [Asset]
    }

    private func fetchLatest() async throws -> (version: String, assetURL: URL) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Contxt/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.http }

        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard let asset = release.assets.first(where: { $0.name.hasSuffix("-macOS.zip") }) else { throw UpdateError.noAsset }
        return (version, asset.browser_download_url)
    }

    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private var updatesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contxt/Updates", isDirectory: true)
    }

    private func stage(version: String, assetURL: URL) async throws {
        setState(.downloading(version))

        let (download, response) = try await URLSession.shared.download(from: assetURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.http }

        let fm = FileManager.default
        let dir = updatesDirectory.appendingPathComponent(version, isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let zip = dir.appendingPathComponent("update.zip")
        try fm.moveItem(at: download, to: zip)
        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        try? fm.removeItem(at: zip)

        let app = dir.appendingPathComponent("Contxt.app")
        guard fm.fileExists(atPath: app.path) else { throw UpdateError.badArchive }
        guard Self.isSignedByCurrentIdentity(app) else {
            try? fm.removeItem(at: dir)
            throw UpdateError.badSignature
        }

        DispatchQueue.main.async {
            self.stagedApp = app
            self.state = .ready(version)
            Toast.show("Contxt \(version) is ready to install")
            self.applyStagedIfAllowed()
        }
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw UpdateError.badArchive }
    }

    /// True if `appURL` satisfies the running app's own designated requirement.
    private static func isSignedByCurrentIdentity(_ appURL: URL) -> Bool {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?

        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(appURL as CFURL, [], &candidate) == errSecSuccess, let candidate else {
            return false
        }
        return SecStaticCodeCheckValidity(candidate, [], requirement) == errSecSuccess
    }

    private func setState(_ new: State) {
        DispatchQueue.main.async { self.state = new }
    }

    // MARK: - Install

    /// Installs a staged update on its own once nothing would be interrupted.
    func applyStagedIfAllowed() {
        guard case .ready = state, Preferences.shared.autoInstallUpdates, isSafeToRestart() else { return }
        installAndRelaunch()
    }

    func installAndRelaunch() {
        guard let staged = stagedApp else { return }

        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent().path
        guard !target.path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: parent) else {
            Toast.show("Move Contxt to Applications to install updates")
            NSWorkspace.shared.activateFileViewerSelecting([staged])
            return
        }

        // Runs after this process exits: swap the bundle (rolling back on
        // failure), clear quarantine, relaunch.
        let script = """
        #!/bin/sh
        PID="$1"; NEW="$2"; TARGET="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        rm -rf "$TARGET.old"
        if mv "$TARGET" "$TARGET.old" && ditto "$NEW" "$TARGET"; then
          rm -rf "$TARGET.old"
        else
          rm -rf "$TARGET"; mv "$TARGET.old" "$TARGET"
        fi
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        open "$TARGET"
        rm -rf "$(dirname "$NEW")"
        """
        let scriptURL = staged.deletingLastPathComponent().appendingPathComponent("install.sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                "-c", "nohup /bin/sh \"$0\" \"$1\" \"$2\" \"$3\" >/dev/null 2>&1 &",
                scriptURL.path, "\(ProcessInfo.processInfo.processIdentifier)", staged.path, target.path,
            ]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            contxtLog("install failed: \(error)")
            Toast.show("Update failed: \(error.localizedDescription)")
        }
    }
}
