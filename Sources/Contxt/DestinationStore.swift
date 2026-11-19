// User-editable list of ring destinations, persisted to
// ~/Library/Application Support/Contxt/destinations.json.

import AppKit

struct DestinationRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case folder, app, script, contact, action, shortcut
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var path: String = ""
    var mode: DropMode = .move
    var action: CommonAction?
    var email: String?
    var phone: String?
    var channel: ContactChannel?
    var avatarPath: String?

    var destination: Destination {
        switch kind {
        case .folder:
            return .folder(id: id.uuidString, label: name, path: path, mode: mode)
        case .app:
            return .app(id: id.uuidString, label: name, appPath: path)
        case .script:
            return .script(id: id.uuidString, label: name, scriptPath: path)
        case .contact:
            return .contact(
                id: id.uuidString,
                label: name,
                target: ContactTarget(email: email, phone: phone, channel: channel ?? .message, avatarPath: avatarPath)
            )
        case .action:
            return .action(id: id.uuidString, label: name, action: action ?? .trash)
        case .shortcut:
            return .shortcut(id: id.uuidString, label: name, name: path) // `path` holds the Shortcuts name
        }
    }
}

final class DestinationStore: ObservableObject {
    static let shared = DestinationStore()

    @Published var records: [DestinationRecord] {
        didSet {
            save()
            onChange?()
        }
    }

    /// Set by the ring so it rebuilds its circles when the list changes.
    var onChange: (() -> Void)?

    let supportDirectory: URL
    private let fileURL: URL

    var destinations: [Destination] { records.map(\.destination) }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contxt", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        supportDirectory = support
        fileURL = support.appendingPathComponent("destinations.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([DestinationRecord].self, from: data) {
            records = saved
        } else {
            records = Self.defaults
        }
    }

    private static var defaults: [DestinationRecord] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            DestinationRecord(kind: .folder, name: "Desktop", path: "\(home)/Desktop"),
            DestinationRecord(kind: .folder, name: "Downloads", path: "\(home)/Downloads"),
            DestinationRecord(kind: .folder, name: "Documents", path: "\(home)/Documents"),
            DestinationRecord(kind: .app, name: "Preview", path: "/System/Applications/Preview.app"),
            DestinationRecord(kind: .app, name: "TextEdit", path: "/System/Applications/TextEdit.app"),
        ]
    }

    func swap(_ idA: String, _ idB: String) {
        guard let a = records.firstIndex(where: { $0.id.uuidString == idA }),
              let b = records.firstIndex(where: { $0.id.uuidString == idB }), a != b else { return }
        records.swapAt(a, b)
    }

    func hasAction(_ action: CommonAction) -> Bool {
        records.contains { $0.kind == .action && $0.action == action }
    }

    func setAction(_ action: CommonAction, enabled: Bool) {
        if enabled {
            guard !hasAction(action) else { return }
            records.append(DestinationRecord(kind: .action, name: action.title, action: action))
        } else {
            records.removeAll { $0.kind == .action && $0.action == action }
        }
    }

    /// Saves a contact photo as a PNG next to the destinations file.
    func saveAvatar(_ data: Data, for id: UUID) -> String? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let dir = supportDirectory.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id.uuidString).png")
        return (try? png.write(to: url)) != nil ? url.path : nil
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
