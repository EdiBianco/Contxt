// AI tools as ring destinations. Each tool (Claude, ChatGPT, Gemini,
// NotebookLM) is one circle; its saved chats open in a searchable list.
// None of these services accept files through a link, so a drop opens the
// chat and leaves the files on the pasteboard for Cmd+V.

import AppKit

enum AITool: String, Codable, CaseIterable, Identifiable {
    case claude, chatgpt, gemini, notebooklm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .notebooklm: return "NotebookLM"
        }
    }

    var hosts: [String] {
        switch self {
        case .claude: return ["claude.ai"]
        case .chatgpt: return ["chatgpt.com", "chat.openai.com"]
        case .gemini: return ["gemini.google.com"]
        case .notebooklm: return ["notebooklm.google.com"]
        }
    }

    var newChatURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/new")!
        case .chatgpt: return URL(string: "https://chatgpt.com/")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        case .notebooklm: return URL(string: "https://notebooklm.google.com/")!
        }
    }

    var color: NSColor {
        switch self {
        case .claude: return NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        case .chatgpt: return NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1)
        case .gemini: return NSColor(red: 0.29, green: 0.47, blue: 0.95, alpha: 1)
        case .notebooklm: return NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        }
    }

    /// Installed desktop apps, used only for the circle's icon.
    private var appBundleIDs: [String] {
        switch self {
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .chatgpt: return ["com.openai.chat"]
        case .gemini: return ["com.google.GeminiMacOS"]
        case .notebooklm: return []
        }
    }

    private var symbol: String {
        switch self {
        case .claude: return "asterisk"
        case .chatgpt: return "bubble.left.and.bubble.right.fill"
        case .gemini: return "sparkle"
        case .notebooklm: return "book.closed.fill"
        }
    }

    var installedApp: URL? {
        appBundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    /// Link that opens a chat inside the desktop app (nil = no app route).
    /// Claude: claude://claude.ai/chat/{id}, /project/{id} (Anthropic docs).
    /// ChatGPT: codex://threads/{id} (OpenAI docs; the app keeps codex://).
    /// A link pasted already in the app's own scheme is used as is.
    func appLink(for link: String) -> URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if url.scheme == "claude" || url.scheme == "codex" { return url }
        switch self {
        case .claude:
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            parts.scheme = "claude"
            return parts.url
        case .chatgpt:
            let comps = url.pathComponents
            guard let i = comps.firstIndex(of: "c"), i + 1 < comps.count else { return nil }
            return URL(string: "codex://threads/\(comps[i + 1])")
        case .gemini, .notebooklm:
            return nil
        }
    }

    /// New chat inside the desktop app.
    var appNewChatLink: URL? {
        switch self {
        case .claude: return URL(string: "claude://claude.ai/new")
        case .chatgpt: return URL(string: "codex://threads/new")
        case .gemini, .notebooklm: return nil
        }
    }

    static func detect(_ link: String) -> AITool? {
        let link = link.trimmingCharacters(in: .whitespaces)
        if link.hasPrefix("claude://") { return .claude }
        if link.hasPrefix("codex://") { return .chatgpt }
        guard let host = URL(string: link)?.host?.lowercased() else { return nil }
        return allCases.first { tool in tool.hosts.contains { host == $0 || host.hasSuffix("." + $0) } }
    }

    func iconImage() -> NSImage {
        for id in appBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        let side: CGFloat = 128
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 28, yRadius: 28)
            self.color.setFill()
            tile.fill()
            let config = NSImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: self.symbol, accessibilityDescription: self.title)?
                .withSymbolConfiguration(config) {
                let s = glyph.size
                glyph.draw(in: NSRect(x: (side - s.width) / 2, y: (side - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
    }
}

struct AIChat: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    var lastUsed: Date?
}
