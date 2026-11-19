// Ported from the Electron prototype's src/common/destinations.ts. The list
// itself lives in DestinationStore (user-editable, persisted as JSON).

import AppKit

/// Default action for a folder destination. Holding Option on drop uses the other one.
enum DropMode: String, Codable, CaseIterable {
    case move
    case copy

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DropMode(rawValue: raw) ?? .move // legacy "auto" becomes move
    }

    var title: String { self == .move ? "Move" : "Copy" }
    var inverted: DropMode { self == .move ? .copy : .move }
}

enum ContactChannel: String, Codable, CaseIterable {
    case message
    case email
    case whatsapp
    case telegram

    var title: String {
        switch self {
        case .message: return "Messages"
        case .email: return "Mail"
        case .whatsapp: return "WhatsApp"
        case .telegram: return "Telegram"
        }
    }
}

/// Built-in actions that aren't a folder, app or script the user picked.
enum CommonAction: String, Codable, CaseIterable {
    case composeMessage
    case composeEmail
    case importPhotos
    case trash

    var title: String {
        switch self {
        case .composeMessage: return "Compose Message"
        case .composeEmail: return "Compose Email"
        case .importPhotos: return "Import to Photos"
        case .trash: return "Move to Trash"
        }
    }

    var detail: String {
        switch self {
        case .composeMessage: return "Send files in Messages"
        case .composeEmail: return "Attach files to a new email"
        case .importPhotos: return "Add to the Photos library"
        case .trash: return "Move files to the Trash"
        }
    }

    var appPath: String? {
        switch self {
        case .composeMessage: return "/System/Applications/Messages.app"
        case .composeEmail: return "/System/Applications/Mail.app"
        case .importPhotos: return "/System/Applications/Photos.app"
        case .trash: return nil
        }
    }
}

struct ContactTarget {
    var email: String?
    var phone: String?
    var channel: ContactChannel
    var avatarPath: String?
}

struct DestinationBadge {
    let symbol: String
    let color: NSColor
}

enum Destination {
    case folder(id: String, label: String, path: String, mode: DropMode = .move)
    case app(id: String, label: String, appPath: String)
    case script(id: String, label: String, scriptPath: String)
    case contact(id: String, label: String, target: ContactTarget)
    case action(id: String, label: String, action: CommonAction)
    case shortcut(id: String, label: String, name: String)

    var id: String {
        switch self {
        case .folder(let id, _, _, _): return id
        case .app(let id, _, _): return id
        case .script(let id, _, _): return id
        case .contact(let id, _, _): return id
        case .action(let id, _, _): return id
        case .shortcut(let id, _, _): return id
        }
    }

    var label: String {
        switch self {
        case .folder(_, let label, _, _): return label
        case .app(_, let label, _): return label
        case .script(_, let label, _): return label
        case .contact(_, let label, _): return label
        case .action(_, let label, _): return label
        case .shortcut(_, let label, _): return label
        }
    }

    /// Small corner badge describing what a drop does; nil for plain apps.
    var badge: DestinationBadge? {
        switch self {
        case .folder(_, _, _, let mode):
            return mode == .move
                ? DestinationBadge(symbol: "arrow.right", color: .systemBlue)
                : DestinationBadge(symbol: "plus", color: .systemGreen)
        case .script:
            return DestinationBadge(symbol: "bolt.fill", color: .systemOrange)
        case .contact(_, _, let target):
            switch target.channel {
            case .message: return DestinationBadge(symbol: "message.fill", color: .systemGreen)
            case .email: return DestinationBadge(symbol: "envelope.fill", color: .systemBlue)
            case .whatsapp:
                return DestinationBadge(symbol: "phone.bubble.fill", color: NSColor(calibratedRed: 0.145, green: 0.827, blue: 0.4, alpha: 1))
            case .telegram:
                return DestinationBadge(symbol: "paperplane.fill", color: NSColor(calibratedRed: 0.165, green: 0.671, blue: 0.933, alpha: 1))
            }
        case .shortcut:
            return DestinationBadge(symbol: "wand.and.stars", color: .systemPurple)
        case .app, .action:
            return nil
        }
    }

    /// Text for the center pill, e.g. "Move to Documents". Option inverts folder actions.
    func actionText(altKeyHeld: Bool) -> String {
        switch self {
        case .folder(_, let label, _, let mode):
            let effective = altKeyHeld ? mode.inverted : mode
            return "\(effective.title) to \(label)"
        case .app(_, let label, _): return "Open with \(label)"
        case .script(_, let label, _): return "Run \(label)"
        case .contact(_, let label, let target):
            switch target.channel {
            case .message: return "Message \(label)"
            case .email: return "Email \(label)"
            case .whatsapp: return "WhatsApp \(label)"
            case .telegram: return "Telegram \(label)"
            }
        case .action(_, _, let action): return action.title
        case .shortcut(_, let label, _): return "Run \u{2018}\(label)\u{2019}"
        }
    }

    func iconImage() -> NSImage {
        switch self {
        case .folder(_, _, let path, _):
            return NSWorkspace.shared.icon(forFile: path)
        case .app(_, _, let path), .script(_, _, let path):
            return NSWorkspace.shared.icon(forFile: path)
        case .contact(_, let label, let target):
            return ContactAvatar.image(name: label, path: target.avatarPath)
        case .action(_, _, let action):
            if let appPath = action.appPath { return NSWorkspace.shared.icon(forFile: appPath) }
            return NSImage(named: NSImage.trashFullName) ?? NSImage()
        case .shortcut:
            return NSWorkspace.shared.icon(forFile: "/System/Applications/Shortcuts.app")
        }
    }
}

enum ContactAvatar {
    private static let side: CGFloat = 128

    static func image(name: String, path: String?) -> NSImage {
        if let path, let photo = NSImage(contentsOfFile: path) {
            return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                NSBezierPath(ovalIn: rect).addClip()
                photo.draw(in: rect)
                return true
            }
        }
        return initials(for: name)
    }

    private static func initials(for name: String) -> NSImage {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let hue = CGFloat(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360

        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor(calibratedHue: hue, saturation: 0.45, brightness: 0.72, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect).fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 52, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let text = letters as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
            return true
        }
    }
}

enum Destinations {
    /// Non-hidden subfolders of `path`.
    static func subfolders(of path: String) -> [(name: String, path: String)] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        return entries
            .filter { !$0.hasPrefix(".") }
            .compactMap { name -> (name: String, path: String)? in
                let full = "\(path)/\(name)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { return nil }
                return (name, full)
            }
    }
}
