// Searchable list of an AI tool's saved chats, shown next to its circle when
// a file is held there. It is its own drop target. The file drag keeps the
// keyboard in the source app, so typing is captured with temporary Carbon
// hotkeys (letters, digits, space, delete) that exist only while the list is open.

import AppKit
import Carbon.HIToolbox

final class ChatListController {
    static let shared = ChatListController()

    private let panel: NSPanel
    private let view = ChatListView()
    private(set) var tool: AITool?
    var onDrop: ((AITool, AIChat?, [URL]) -> Void)?

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        view.onDrop = { [weak self] chat, urls in
            guard let self, let tool = self.tool else { return }
            self.hide()
            self.onDrop?(tool, chat, urls)
        }
    }

    var isVisible: Bool { panel.isVisible }

    /// `anchor` is the circle's frame in screen coordinates; the list opens on
    /// whichever side has room.
    func show(tool: AITool, chats: [AIChat], beside anchor: NSRect) {
        self.tool = tool
        view.load(tool: tool, chats: chats)
        let size = view.preferredSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.maxX + 10
        if x + size.width > screen.maxX { x = anchor.minX - 10 - size.width }
        let y = min(max(anchor.midY - size.height + 40, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        TypeCapture.shared.start { [weak self] key in self?.view.type(key) }
    }

    func hide() {
        TypeCapture.shared.stop()
        panel.orderOut(nil)
        tool = nil
    }
}

private final class ChatListView: NSView {
    private struct Row { let chat: AIChat?; let title: String; let detail: String }

    private static let width: CGFloat = 300
    private static let rowHeight: CGFloat = 40
    private static let maxRows = 7

    var onDrop: ((AIChat?, [URL]) -> Void)?
    private var tool: AITool = .claude
    private var chats: [AIChat] = []
    private var query = ""
    private var rows: [Row] = []
    private var hovered: Int?
    private var icon = NSImage()

    private let effect = NSVisualEffectView()
    private let header = NSTextField(labelWithString: "")
    private let search = NSTextField(labelWithString: "")
    private let rowsView = FlippedView()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        addSubview(effect)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        search.font = .systemFont(ofSize: 13)
        effect.addSubview(header)
        effect.addSubview(search)
        effect.addSubview(rowsView)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    var preferredSize: NSSize {
        NSSize(width: Self.width, height: 74 + CGFloat(max(rows.count, 1)) * Self.rowHeight + 8)
    }

    func load(tool: AITool, chats: [AIChat]) {
        self.tool = tool
        self.chats = chats.sorted { ($0.lastUsed ?? .distantPast, $1.name) > ($1.lastUsed ?? .distantPast, $0.name) }
        icon = tool.iconImage()
        query = ""
        hovered = nil
        rebuild()
    }

    func type(_ key: TypeCapture.Key) {
        switch key {
        case .char(let c): query.append(c)
        case .delete: if !query.isEmpty { query.removeLast() }
        }
        hovered = nil
        rebuild()
        if let window {
            let size = preferredSize
            var frame = window.frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            window.setFrame(frame, display: true)
        }
    }

    private func rebuild() {
        let q = query.lowercased()
        let matches = chats.filter { q.isEmpty || $0.name.lowercased().contains(q) }
        rows = [Row(chat: nil, title: "New \(tool.title) chat", detail: "Start fresh")]
            + matches.prefix(Self.maxRows).map { Row(chat: $0, title: $0.name, detail: URL(string: $0.url)?.host ?? $0.url) }

        let size = preferredSize
        frame = NSRect(origin: .zero, size: size)
        effect.frame = bounds
        header.stringValue = tool.title.uppercased() + "  \u{00B7}  RELEASE ON A CHAT"
        header.frame = NSRect(x: 16, y: size.height - 30, width: size.width - 32, height: 16)
        search.stringValue = query.isEmpty ? "Type to filter" : query
        search.textColor = query.isEmpty ? .tertiaryLabelColor : .labelColor
        search.frame = NSRect(x: 16, y: size.height - 58, width: size.width - 32, height: 20)

        rowsView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - 66)
        rowsView.subviews.forEach { $0.removeFromSuperview() }
        for (i, row) in rows.enumerated() {
            rowsView.addSubview(rowView(row, index: i))
        }
    }

    private func rowView(_ row: Row, index: Int) -> NSView {
        let v = NSView(frame: NSRect(x: 6, y: 4 + CGFloat(index) * Self.rowHeight, width: Self.width - 12, height: Self.rowHeight))
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.backgroundColor = index == hovered ? NSColor.white.withAlphaComponent(0.16).cgColor : nil

        let img = NSImageView(frame: NSRect(x: 10, y: 9, width: 22, height: 22))
        img.image = row.chat == nil ? NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil) : icon
        img.contentTintColor = .secondaryLabelColor
        v.addSubview(img)

        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 42, y: 20, width: v.frame.width - 52, height: 16)
        v.addSubview(title)

        let detail = NSTextField(labelWithString: row.detail)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.frame = NSRect(x: 42, y: 4, width: v.frame.width - 52, height: 14)
        v.addSubview(detail)
        return v
    }

    private func row(at windowPoint: NSPoint) -> Int? {
        let p = rowsView.convert(windowPoint, from: nil)
        guard p.x >= 0, p.x <= rowsView.bounds.width else { return nil }
        let i = Int((p.y - 4) / Self.rowHeight)
        return p.y >= 4 && i < rows.count ? i : nil
    }

    private func setHovered(_ i: Int?) {
        guard i != hovered else { return }
        hovered = i
        for (n, v) in rowsView.subviews.enumerated() {
            v.layer?.backgroundColor = n == i ? NSColor.white.withAlphaComponent(0.16).cgColor : nil
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        setHovered(row(at: sender.draggingLocation))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        setHovered(row(at: sender.draggingLocation))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setHovered(nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let i = row(at: sender.draggingLocation) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(rows[i].chat, urls)
        return true
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Typing while a file is being dragged

private func typeCaptureHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard id.signature == TypeCapture.signature else { return CallNextEventHandler(next, event) }
    TypeCapture.shared.fire(Int(id.id))
    return noErr
}

final class TypeCapture {
    enum Key { case char(Character), delete }

    static let shared = TypeCapture()
    static let signature: FourCharCode = 0x4354_5833 // "CTX3"

    private static let keys: [(code: Int, key: Key)] = {
        let letters: [(Int, Character)] = [
            (kVK_ANSI_A, "a"), (kVK_ANSI_B, "b"), (kVK_ANSI_C, "c"), (kVK_ANSI_D, "d"), (kVK_ANSI_E, "e"),
            (kVK_ANSI_F, "f"), (kVK_ANSI_G, "g"), (kVK_ANSI_H, "h"), (kVK_ANSI_I, "i"), (kVK_ANSI_J, "j"),
            (kVK_ANSI_K, "k"), (kVK_ANSI_L, "l"), (kVK_ANSI_M, "m"), (kVK_ANSI_N, "n"), (kVK_ANSI_O, "o"),
            (kVK_ANSI_P, "p"), (kVK_ANSI_Q, "q"), (kVK_ANSI_R, "r"), (kVK_ANSI_S, "s"), (kVK_ANSI_T, "t"),
            (kVK_ANSI_U, "u"), (kVK_ANSI_V, "v"), (kVK_ANSI_W, "w"), (kVK_ANSI_X, "x"), (kVK_ANSI_Y, "y"),
            (kVK_ANSI_Z, "z"), (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9"), (kVK_Space, " "),
        ]
        return letters.map { ($0.0, Key.char($0.1)) } + [(kVK_Delete, .delete)]
    }()

    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var onKey: ((Key) -> Void)?

    func start(_ onKey: @escaping (Key) -> Void) {
        stop()
        self.onKey = onKey
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), typeCaptureHandler, 1, &spec, nil, &handlerRef)
        }
        for (i, entry) in Self.keys.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(i))
            if RegisterEventHotKey(UInt32(entry.code), 0, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    func stop() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        onKey = nil
    }

    fileprivate func fire(_ index: Int) {
        guard Self.keys.indices.contains(index) else { return }
        onKey?(Self.keys[index].key)
    }
}
