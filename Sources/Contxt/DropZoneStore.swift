// Files collected in the Drop Zone (the ring's central circle). Holds
// references only — nothing is moved or copied until the stack is dragged
// out into a Finder folder, so a staged file is never at risk.

import Foundation

final class DropZoneStore: ObservableObject {
    static let shared = DropZoneStore()

    @Published private(set) var urls: [URL] = []

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contxt", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("dropzone.json")

        if let data = try? Data(contentsOf: fileURL), let paths = try? JSONDecoder().decode([String].self, from: data) {
            urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func add(_ new: [URL]) {
        let existing = Set(urls.map(\.path))
        urls += new.filter { !existing.contains($0.path) }
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0.path == url.path }
        save()
    }

    func clear() {
        urls = []
        save()
    }

    /// Drops entries whose files disappeared (moved or deleted elsewhere).
    func prune() {
        let alive = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard alive.count != urls.count else { return }
        urls = alive
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(urls.map(\.path)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
